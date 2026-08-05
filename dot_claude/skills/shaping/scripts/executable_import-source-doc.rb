#!/usr/bin/env ruby
# frozen_string_literal: true

# import-source-doc — the deterministic half of importing an external source
# document (Google Doc, Word doc, exported HTML) into a shaping project.
#
# Claude does the judgement work: fetching via MCP, naming the screenshots,
# spotting gaps. This script does everything mechanical, so it can't drift:
# decoding the export, extracting inline images to disk, splicing image refs
# into the markdown body at their original positions, and verifying refs.
#
#   import-source-doc.rb import --project SLUG --export PATH [options]
#   import-source-doc.rb rename --project SLUG 01=daily-view-graph 02=...
#   import-source-doc.rb verify --project SLUG
#
# Run `import-source-doc.rb help` for the full option list.

require "base64"
require "date"
require "fileutils"
require "json"
require "optparse"

NOTES_ROOT = File.expand_path("~/notes/shaping")
IMAGE_DIR = "images"
PLACEHOLDER = /\\?\[image\\?\]/

# Reads a Drive/MCP export payload off disk, whatever shape it arrived in.
#
# Oversized MCP results get spilled to a JSON file rather than returned inline,
# which is the whole point: a base64 HTML export must never be round-tripped
# through a model's context. Handles that JSON, a bare JSON payload, or a plain
# HTML/markdown file.
class Export
  BASE64_KEYS = %w[content fileContent].freeze

  def self.load(path)
    raise "export not found: #{path}" unless File.file?(path)

    new(File.read(path, mode: "rb").force_encoding("UTF-8"))
  end

  def initialize(raw)
    @raw = raw
  end

  def text
    @text ||= decode(unwrap_json)
  end

  private

  def unwrap_json
    return @raw unless @raw.lstrip.start_with?("{")

    payload = JSON.parse(@raw)
    key = BASE64_KEYS.find { payload[it].is_a?(String) }
    key ? payload.fetch(key) : @raw
  rescue JSON::ParserError
    @raw
  end

  def decode(body)
    return body if body.match?(/[<#\n]/) && !base64?(body)

    Base64.strict_decode64(body.strip).force_encoding("UTF-8")
  rescue ArgumentError
    body
  end

  def base64?(body)
    body.strip.match?(%r{\A[A-Za-z0-9+/\r\n]+={0,2}\z})
  end
end

# One inline image pulled out of an HTML export.
Image = Struct.new(:index, :ext, :bytes, :dimensions, :context, :filename) do
  def to_s
    format("%2d. %-22s %8d bytes  %-11s | preceded by: ...%s",
      index, filename, bytes, dimensions || "?", context)
  end
end

# Pulls `data:` URI images out of an HTML export and writes them to disk,
# recording the surrounding text so each one can be named meaningfully.
class ImageExtractor
  DATA_URI = %r{data:image/(\w+);base64,([A-Za-z0-9+/=\s]+?)(?=["')])}

  def initialize(html, dir)
    @html = html
    @dir = dir
  end

  # Returns [images, rewritten_html] — the html with each data URI swapped for
  # its on-disk path, so source.html stays openable without a 300KB payload.
  def extract
    FileUtils.mkdir_p(File.join(@dir, IMAGE_DIR))
    images = []

    rewritten = @html.gsub(DATA_URI) do
      ext = normalise_ext(Regexp.last_match(1))
      data = Base64.decode64(Regexp.last_match(2))
      index = images.size + 1
      filename = format("image-%02d.%s", index, ext)
      File.binwrite(File.join(@dir, IMAGE_DIR, filename), data)

      images << Image.new(
        index:, ext:, bytes: data.bytesize,
        dimensions: png_dimensions(data),
        context: preceding_words(Regexp.last_match.begin(0)),
        filename:
      )
      "#{IMAGE_DIR}/#{filename}"
    end

    [images, rewritten]
  end

  private

  def normalise_ext(ext)
    (ext == "jpeg") ? "jpg" : ext
  end

  def png_dimensions(data)
    return nil unless data.start_with?("\x89PNG".b)

    width, height = data[16, 8].unpack("N2")
    "#{width}x#{height}"
  end

  def preceding_words(offset)
    @html[0, offset]
      .gsub(/<style[^>]*>.*?<\/style>/m, " ")
      .gsub(/<[^>]+>/, " ")
      .sub(/<[^>]*\z/, " ")
      .gsub(/&[a-z]+;|&#\d+;/, " ")
      .split
      .last(12)
      .join(" ")
  end
end

# Rebuilds the document body as markdown with local image refs in place.
#
# Prefers the MCP `read_file_content` markdown (which keeps headings, lists and
# tables) and splices image refs into its `[image]` placeholders. Placeholder
# order matches HTML source order, so a count mismatch means the two exports
# disagree — that aborts rather than silently misplacing screenshots.
class Body
  # Markdown escapes the MCP adds mechanically. Unescaping punctuation with no
  # markdown meaning restores the author's text; structural chars stay escaped.
  INERT_ESCAPES = /\\([!?:;%&'",@\/()])/

  def initialize(markdown:, html:, images:)
    @markdown = markdown
    @html = html
    @images = images
  end

  def markdown?
    !@markdown.nil?
  end

  def placeholders
    markdown? ? @markdown.scan(PLACEHOLDER).size : 0
  end

  def render
    markdown? ? splice_markdown : flatten_html
  end

  # Headings with nothing under them — the author left them blank. Worth
  # surfacing: they're usually the sections shaping most needs filled in.
  # The document's own title heading is skipped; a title is always followed by
  # the first real heading and is never an empty section.
  def empty_sections
    return [] unless markdown?

    lines = @markdown.lines.map(&:rstrip)
    headings = lines.each_index.select { lines[it].match?(/^#+\s+\S/) }
    headings.drop(1).filter_map do |i|
      following = lines[(i + 1)..].reject(&:empty?).first
      lines[i].sub(/^#+\s+/, "") if following.nil? || following.match?(/^#+\s+/)
    end
  end

  private

  def splice_markdown
    queue = @images.dup
    @markdown
      .gsub(PLACEHOLDER) { image_ref(queue.shift) }
      .gsub(INERT_ESCAPES, '\1')
      .strip
  end

  def image_ref(image)
    return "[image: MISSING]" unless image

    "![](#{IMAGE_DIR}/#{image.filename})"
  end

  def flatten_html
    @html
      .sub(/\A.*?<body[^>]*>/m, "")
      .gsub(/<style[^>]*>.*?<\/style>/m, "")
      .gsub(/<img[^>]*src="([^"]+)"[^>]*>/) { "\n![](#{Regexp.last_match(1)})\n" }
      .gsub(/<\/(p|h\d|li|tr|div)>/, "\n")
      .gsub(/<[^>]+>/, "")
      .then { unescape_entities(it) }
      .lines.map(&:strip).reject(&:empty?).join("\n\n")
  end

  def unescape_entities(text)
    entities = {
      "&nbsp;" => " ", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">",
      "&quot;" => '"', "&#39;" => "'", "&rsquo;" => "’", "&lsquo;" => "‘",
      "&rdquo;" => "”", "&ldquo;" => "“", "&hellip;" => "…", "&mdash;" => "—", "&ndash;" => "–"
    }
    text.gsub(/&\w+;|&#\d+;/) { entities.fetch(it, it) }
  end
end

# Writes the project's requirements doc: shaping frontmatter, a provenance
# block, then the source document verbatim.
class RequirementsDoc
  def initialize(dir:, filename:, meta:, body:)
    @path = File.join(dir, filename)
    @meta = meta
    @body = body
  end

  attr_reader :path

  def write(image_count)
    File.write(@path, <<~DOC)
      ---
      shaping: true
      ---

      # #{@meta[:title]} — Source Requirements

      ## Source

      #{provenance.join("\n")}

      Everything below is the source document verbatim. Images are extracted to
      `#{IMAGE_DIR}/` and inlined at their original positions.

      ---

      #{@body}
    DOC
    @path
  end

  private

  def provenance
    lines = []
    lines << (@meta[:url] ? "- Document: [#{@meta[:title]}](#{@meta[:url]})" : "- Document: #{@meta[:title]}")
    lines << "- Owner: #{@meta[:owner]}" if @meta[:owner]
    lines << timestamps if @meta[:created] || @meta[:modified]
    lines << "- Retrieved: #{Date.today} — #{@meta[:image_count]} image(s), #{@meta[:comments]}"
    lines.compact
  end

  def timestamps
    parts = []
    parts << "Created: #{@meta[:created]}" if @meta[:created]
    parts << "Last modified: #{@meta[:modified]}" if @meta[:modified]
    "- #{parts.join(" · ")}"
  end
end

# Renames extracted images to meaningful slugs and repoints every reference.
class Renamer
  def initialize(dir)
    @dir = dir
  end

  def apply(mapping)
    renamed = mapping.filter_map { |index, slug| rename_one(index, slug) }
    repoint(renamed)
    renamed
  end

  private

  def rename_one(index, slug)
    current = Dir.glob(File.join(@dir, IMAGE_DIR, "image-#{index}.*")).first
    unless current
      warn "no image-#{index}.* in #{@dir}/#{IMAGE_DIR} — skipped"
      return nil
    end

    target = format("%s-%s%s", index, slug, File.extname(current))
    File.rename(current, File.join(@dir, IMAGE_DIR, target))
    [File.basename(current), target]
  end

  def repoint(renamed)
    Dir.glob(File.join(@dir, "*.{md,html}")).each do |file|
      text = File.read(file)
      updated = renamed.reduce(text) do |acc, (old, new)|
        acc.gsub("#{IMAGE_DIR}/#{old}", "#{IMAGE_DIR}/#{new}")
      end
      File.write(file, updated) unless updated == text
    end
  end
end

# Confirms every image reference resolves and flags images nobody references.
class Verifier
  def initialize(dir)
    @dir = dir
  end

  def run
    refs = referenced
    missing = refs.reject { File.file?(File.join(@dir, it)) }
    orphans = on_disk - refs

    refs.sort.each { puts "  OK      #{it}" }
    missing.sort.each { puts "  MISSING #{it}" }
    orphans.sort.each { puts "  ORPHAN  #{it} (on disk, unreferenced)" }
    puts "\n#{refs.size} reference(s), #{missing.size} missing, #{orphans.size} orphan(s)"
    missing.empty?
  end

  private

  def referenced
    Dir.glob(File.join(@dir, "*.{md,html}"))
      .flat_map { File.read(it).scan(%r{#{IMAGE_DIR}/[\w.-]+\.\w+}o) }
      .uniq
  end

  def on_disk
    Dir.glob(File.join(@dir, IMAGE_DIR, "*")).map { "#{IMAGE_DIR}/#{File.basename(it)}" }
  end
end

# Command-line front end.
class CLI
  def self.run(argv)
    command = argv.shift
    case command
    when "import" then new.import(argv)
    when "rename" then new.rename(argv)
    when "verify" then new.verify(argv)
    when "help", "--help", "-h", nil then puts usage
    else
      warn "unknown command: #{command}\n\n#{usage}"
      exit 1
    end
  end

  def self.usage
    <<~USAGE
      Usage:
        import-source-doc.rb import --project SLUG --export PATH [options]
        import-source-doc.rb rename --project SLUG 01=slug 02=slug ...
        import-source-doc.rb verify --project SLUG

      import options:
        --project SLUG     project dir under ~/notes/shaping (required)
        --export PATH      HTML export: MCP tool-result JSON, or a .html file (required)
        --markdown PATH    MCP read_file_content markdown — strongly preferred,
                           keeps headings/lists/tables that HTML flattening loses
        --title TITLE      document title
        --url URL          document URL
        --owner EMAIL      document owner
        --created DATE     creation date
        --modified DATE    last-modified date
        --comments TEXT    e.g. "no comments" or "3 comment threads"
        --doc FILENAME     output filename (default: source-requirements.md)
        --notes-dir DIR    override ~/notes/shaping
    USAGE
  end

  def import(argv)
    opts = parse(argv, %i[project export markdown title url owner created modified comments doc notes-dir])
    dir = project_dir(opts)
    FileUtils.mkdir_p(dir)

    html = Export.load(File.expand_path(opts.fetch(:export))).text
    images, rewritten = ImageExtractor.new(html, dir).extract
    markdown = opts[:markdown] ? Export.load(File.expand_path(opts[:markdown])).text : nil
    # Flattening must work from the rewritten HTML, or every base64 data URI
    # ends up inlined in the markdown body.
    body = Body.new(markdown:, html: rewritten, images:)

    check_placeholders(body, images)
    File.write(File.join(dir, "source.html"), rewritten)

    doc = RequirementsDoc.new(
      dir:,
      filename: opts.fetch(:doc, "source-requirements.md"),
      meta: metadata(opts, images),
      body: body.render
    ).write(images.size)

    report(dir:, doc:, images:, body:)
  end

  def rename(argv)
    mapping = argv.grep(/\A\d+=/).map { it.split("=", 2) }
    opts = parse(argv.reject { it.include?("=") }, %i[project notes-dir])
    abort "nothing to rename — pass mappings like 01=daily-view-graph" if mapping.empty?

    dir = project_dir(opts)
    Renamer.new(dir).apply(mapping).each { |old, new| puts "  #{old} -> #{new}" }
    puts
    Verifier.new(dir).run
  end

  def verify(argv)
    opts = parse(argv, %i[project notes-dir])
    exit(Verifier.new(project_dir(opts)).run ? 0 : 1)
  end

  private

  def parse(argv, allowed)
    opts = {}
    parser = OptionParser.new do |o|
      allowed.each { |name| o.on("--#{name} VALUE") { |v| opts[name.to_s.tr("-", "_").to_sym] = v } }
    end
    parser.parse(argv)
    opts
  end

  def project_dir(opts)
    slug = opts[:project] or abort "--project is required"
    File.join(opts.fetch(:notes_dir) { NOTES_ROOT }, slug)
  end

  def metadata(opts, images)
    {
      title: opts.fetch(:title, opts.fetch(:project)),
      url: opts[:url],
      owner: opts[:owner],
      created: opts[:created],
      modified: opts[:modified],
      comments: opts.fetch(:comments, "comments not checked"),
      image_count: images.size
    }
  end

  # A mismatch means the markdown and HTML exports disagree about how many
  # images the document has, so splicing would put screenshots in the wrong
  # place. Fail loudly instead.
  def check_placeholders(body, images)
    return unless body.markdown?
    return if body.placeholders == images.size

    abort <<~ERROR
      Placeholder mismatch: #{body.placeholders} [image] placeholder(s) in the markdown
      but #{images.size} image(s) in the HTML export. Splicing would misplace screenshots.
      Re-fetch both exports for the same revision, or drop --markdown to flatten the HTML.
    ERROR
  end

  def report(dir:, doc:, images:, body:)
    puts "Project:  #{dir}"
    puts "Doc:      #{doc}"
    puts "Source:   #{File.join(dir, "source.html")}"
    puts "Body:     #{body.markdown? ? "spliced MCP markdown" : "flattened HTML (headings/tables lost)"}"
    puts "\nImages (#{images.size}) — rename these with the `rename` command:"
    images.each { puts "  #{it}" }

    empty = body.empty_sections
    return if empty.empty?

    puts "\nEmpty sections in source (flag these to the user):"
    empty.each { puts "  - #{it}" }
  end
end

CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
