#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the PR study page: every open PR as a plant in a garden, each with a
# diagram of what the change does and the comprehension questions worth answering
# about it. Opening a plant's sheet is a plain link and `:target` CSS, so Vimium
# does the navigating; the only script is Escape-to-close.
#
# Reads the status of each PR from the newest record collect.rb wrote, and the
# diagram plus questions from ~/.local/share/productivity/study/<number>.json.
#
# Usage: study.rb             render diagrams, build the page, open it on change
#        study.rb --stale     list the PRs whose diagram/questions need writing
#        study.rb --no-open   build the page without ever opening it

require "json"
require "time"
require "cgi"
require "fileutils"
require "open3"

DATA_DIR = File.join(Dir.home, ".local", "share", "productivity")
STUDY_DIR = File.join(DATA_DIR, "study")
PAGE_PATH = File.join(DATA_DIR, "study.html")
SIGNATURE_PATH = File.join(STUDY_DIR, ".page-signature")
RENDERER = File.join(Dir.home, ".local", "share", "mermaid-render", "render.mjs")

# Lines that configure the diagram rather than label anything in it.
DIRECTIVE = /^\s*(class|style|linkStyle|participant|actor|%%)/

# Node text, and any quoted label, sits enclosed. Used both to collect labels and
# to blank them out before looking for what follows an arrow.
ENCLOSED = /\[[^\]\[]+\]|\{[^}{]+\}|\([^)(]+\)|"[^"]+"/

def today = Time.now.strftime("%Y-%m-%d")

# collect.rb's newest record. It already derives every status field this page
# shows — build_state, settled, stack_base, idle_days — so nothing is recomputed
# here.
def latest_tick
  log = File.join(DATA_DIR, "#{today}.jsonl")
  abort "No tick recorded today. Run collect.rb first." unless File.exist?(log)

  last = File.readlines(log).reverse.find { !it.strip.empty? }
  abort "#{log} is empty. Run collect.rb first." unless last

  JSON.parse(last)
rescue JSON::ParserError => error
  abort "Could not read #{log}: #{error.message}"
end

def open_prs = Array(latest_tick.dig("github", "in_flight")).sort_by { it["pushed_commit_at"].to_s }.reverse

# Read once per PR per run: both the page build and the change signature ask for
# the same entries. `fetch` with a block memoises a nil result too, which `||=`
# would re-read every time.
def entry(number) = (@entries ||= {}).fetch(number) { @entries[number] = read_entry(number) }

def read_entry(number)
  path = File.join(STUDY_DIR, "#{number}.json")
  return nil unless File.exist?(path)

  JSON.parse(File.read(path))
rescue JSON::ParserError
  nil
end

# A PR needs writing when nothing has been written for it, when what was written
# describes an older head commit, or when the entry carries no diagram source.
def stale?(pr)
  written = entry(pr["number"])
  return true unless written

  written["head_sha"] != pr["head_sha"] || written.dig("diagram", "mmd").to_s.strip.empty?
end

# Everything a payaus title carries before it says what the PR does: its stack
# position, its ticket reference, its type. They come in any order, so strip until
# nothing more comes off.
def age_label(age_in_days)
  return "#{(age_in_days * 24).round}h" if age_in_days < 1

  "#{age_in_days.round}d"
end

# A flowering PR is one that's genuinely done with the developer: ready, green and
# quiet. That is exactly what the collector's `settled` means, so read it rather
# than re-deriving a weaker version. Everything still theirs is a plant that wilts
# the longer it goes untended.
def flowering?(pr) = pr["settled"]

# How far past tending a PR is, 0 to 1. Six working days of silence is fully gone.
# A PR set aside on purpose is overwintered, not neglected — it never wilts, because
# wilting is what asks the developer for attention.
def neglect(pr) = pr["on_hold"] ? 0.0 : [pr["idle_days"].to_f / 6.0, 1.0].min

def blend(from, to, ratio)
  low, high = [from, to].map { it.scan(/\h\h/).map { |part| part.to_i(16) } }
  format("#%02x%02x%02x", *low.zip(high).map { |start, finish| (start + ((finish - start) * ratio)).round })
end

def soil_style(pr)
  hue = [100 - (neglect(pr) * 74), 26].max.round
  "--soil: hsl(#{hue}, 20%, 13%)"
end

# A point on the stem's quadratic curve, so leaves and the bloom sit on the stalk
# however far it has bent over.
def along(origin, control, tip, ratio)
  inverse = 1 - ratio
  origin.zip(control, tip).map do |from, via, to|
    (inverse**2 * from) + (2 * inverse * ratio * via) + (ratio**2 * to)
  end
end

# The plant is not an icon of the PR's state, it is a drawing of its numbers: the
# stem grows with the days the PR has been open, bends and browns with the days
# since it was last touched, and blooms once the work is green and off the
# developer's hands.
def plant_svg(pr)
  gone = neglect(pr)
  bloom = flowering?(pr)
  height = [26 + (pr["age_days"].to_f * 3.4), 60].min
  bend = bloom ? 0 : gone * 26

  origin = [30, 88]
  tip = [30 + bend, 88 - height + (bend * 0.5)]
  control = [30 + (bend * 0.2), 88 - (height * 0.62)]
  stem = blend("#b8bb26", "#7c6f64", gone)
  leaf = blend("#98971a", "#af3a03", gone)

  <<~SVG
    <svg viewBox="0 0 68 92" width="100%" height="100%" aria-hidden="true">
      <path d="M#{origin[0]} #{origin[1]} Q#{control.join(" ")} #{tip.join(" ")}"
            fill="none" stroke="#{stem}" stroke-width="2.4" stroke-linecap="round"/>
      #{leaves(origin, control, tip, leaf, bend)}
      #{bloom ? blossom(tip) : bud(tip, stem)}
    </svg>
  SVG
end

def leaves(origin, control, tip, colour, bend)
  [[0.42, -1], [0.66, 1]].map do |ratio, side|
    x, y = along(origin, control, tip, ratio)
    lean = (side * 34) + (bend * 0.7)
    %(<ellipse cx="#{(x + (side * 8)).round(1)}" cy="#{y.round(1)}" rx="8.5" ry="3.6" fill="#{colour}"
        transform="rotate(#{lean.round(1)} #{x.round(1)} #{y.round(1)})"/>)
  end.join("\n      ")
end

def blossom(tip)
  petals = (0..4).map do |index|
    angle = (index * 72) * Math::PI / 180
    %(<circle cx="#{(tip[0] + (Math.cos(angle) * 5.2)).round(1)}" cy="#{(tip[1] + (Math.sin(angle) * 5.2)).round(1)}" r="4" fill="#fabd2f"/>)
  end
  "#{petals.join("\n      ")}\n      <circle cx=\"#{tip[0].round(1)}\" cy=\"#{tip[1].round(1)}\" r=\"2.6\" fill=\"#d79921\"/>"
end

def bud(tip, colour) = %(<circle cx="#{tip[0].round(1)}" cy="#{tip[1].round(1)}" r="3.1" fill="#{colour}"/>)

# Every label the source asks for, so a silently-dropped line can be caught. The
# renderer discards anything it can't parse without a word of complaint — a
# reversed ER cardinality loses its whole relationship at exit 0.
def source_labels(mmd)
  mmd.to_s.lines.reject { it.match?(DIRECTIVE) }
    .flat_map { line_labels(it) }
    .map { it.gsub(/\A["']|["']\z/, "").strip }
    .reject(&:empty?)
    .uniq
end

# Node text sits inside brackets; message, transition and relationship text
# follows the colon after an arrow. Bracketed segments are lifted out first so a
# colon inside a node label — a path like /shifts/:id — is never mistaken for a
# message label.
def line_labels(raw)
  line = raw.rstrip
  enclosed = line.scan(ENCLOSED).map { it[1..-2] }
  bare = line.gsub(ENCLOSED, "")
  after_arrow = bare[/(?:-->>|->>|-->|--x|-x|--\)|==>|--)[^:]*:\s*(.+)\z/, 1]
  note = line[/\A\s*[Nn]ote\s[^:]*:\s*(.+)\z/, 1]
  enclosed + [after_arrow, note].compact
end

def svg_labels(svg) = svg.scan(%r{<text[^>]*>(.*?)</text>}m).flatten.map { CGI.unescapeHTML(it.gsub(/<[^>]+>/, "")) }

def missing_labels(mmd, svg)
  rendered = svg_labels(svg).join("\n")
  source_labels(mmd).reject { rendered.include?(it) }
end

def render_svg(mmd)
  svg, error, status = Open3.capture3("node", RENDERER, stdin_data: mmd)
  return [nil, error.strip] unless status.success?

  [svg, nil]
end

def escape(text) = CGI.escapeHTML(text.to_s)

def question_html(question)
  evidence = Array(question["evidence"]).map { "<li>#{escape(it)}</li>" }.join
  cited = evidence.empty? ? "" : "<ul class=\"evidence\">#{evidence}</ul>"
  <<~HTML
    <details>
      <summary>#{escape(question["question"])}</summary>
      <p class="answer">#{escape(question["answer"])}</p>
      #{cited}
    </details>
  HTML
end

# One stake per open PR, driven into its own colour of earth. The plant walks down
# to that PR's specimen sheet — the row is where you notice something needs
# tending, the sheet below is where you tend it. The variety name links out to
# GitHub.
def title_html(pr) = escape(pr["handle"])

def sown_label(pr) = age_label(pr["age_days"].to_f)

def plant_card(pr, state:, written:, sheet:)
  count = Array(written["questions"]).size
  label = count.zero? ? "no notes yet" : "#{count} note#{"s" if count > 1}"
  notes = sheet ? "<a class=\"notes\" href=\"#pr-#{pr["number"]}\">#{label}</a>" : "<div class=\"notes idle\">#{label}</div>"

  <<~HTML
    <div class="stake#{" bloomed" if flowering?(pr)}" style="#{soil_style(pr)}">
      <a class="specimen" href="#{sheet ? "#pr-#{pr["number"]}" : escape(pr["url"])}" title="#{title_html(pr)}">#{plant_svg(pr)}</a>
      <div class="plaque">
        <a class="variety" href="#{escape(pr["url"])}">#{title_html(pr)}</a>
        <div class="sown">##{pr["number"]} · sown #{sown_label(pr)}</div>
        <div class="state">#{escape(state)}</div>
        #{notes}
      </div>
    </div>
  HTML
end

def section_html(pr, state:, written:, svg:, warning:)
  questions = Array(written["questions"]).map { question_html(it) }.join
  notes = questions.empty? ? "" : "<p class=\"eyebrow\">Field notes</p>#{questions}"
  body = svg ? "#{warning}<div class=\"diagram\">#{svg}</div>#{notes}" : warning

  <<~HTML
    <div class="sheet" id="pr-#{pr["number"]}">
      <a class="scrim" href="#" aria-label="Close"></a>
      <article>
      <a class="close" href="#" aria-label="Close">&times;</a>
      <h2><a href="#{escape(pr["url"])}">#{title_html(pr)}<span class="num">##{pr["number"]}</span></a></h2>
      <p class="meta">#{escape(pr["head_branch"])} · #{escape(state)} · sown #{sown_label(pr)}</p>
      #{body}
      </article>
    </div>
  HTML
end

def styles
  <<~CSS
    :root { --plate: Superclarendon, "Iowan Old Style", Charter, Georgia, serif;
            --data: ui-monospace, "SF Mono", Menlo, monospace; }
    body { margin: 0; padding: 30px 40px 90px; background: #1d2021; color: #ebdbb2;
           font-family: var(--plate); line-height: 1.5; }
    h1 { font-size: 21px; font-weight: 600; letter-spacing: 0.01em; margin: 0 0 18px; }
    h1 .when { font-family: var(--data); font-size: 11px; font-weight: 400; color: #928374;
               letter-spacing: 0.08em; text-transform: uppercase; margin-left: 12px; }

    /* One planted row: stakes flush against each other, each in its own earth. */
    .row { display: flex; flex-wrap: wrap; gap: 1px; border-radius: 3px; overflow: hidden;
           margin-bottom: 12px; }
    .stake { flex: 1 1 clamp(144px, 11vw, 196px); background: var(--soil);
             display: flex; flex-direction: column; }
    .specimen { display: block; height: clamp(88px, 9vw, 132px); padding-top: 12px; }
    .specimen svg { display: block; height: 100%; }
    .bloomed .specimen svg { animation: sway 6s ease-in-out infinite; transform-origin: 50% 96%; }
    @keyframes sway { 0%, 100% { transform: rotate(-1.6deg); } 50% { transform: rotate(1.6deg); } }
    .plaque { background: rgba(29,32,33,0.55); border-top: 1px solid rgba(168,153,132,0.16);
              padding: 9px 11px 12px; flex-grow: 1; }
    .variety { display: block; font-size: 12.5px; line-height: 1.32; color: #ebdbb2;
               text-decoration: none; }
    .variety:hover { text-decoration: underline; }
    .sown, .state, .notes { font-family: var(--data); font-size: 10px; letter-spacing: 0.06em;
                            text-transform: uppercase; }
    .sown { color: #928374; margin-top: 7px; }
    .state { color: #a89984; margin-top: 3px; }
    .notes { display: block; margin-top: 7px; color: #b8bb26; text-decoration: none; }
    a.notes:hover { text-decoration: underline; }
    .notes.idle { color: #665c54; }
    .waiting { font-family: var(--data); font-size: 10px; letter-spacing: 0.06em;
               text-transform: uppercase; color: #7c6f64; margin: 0 0 40px; }

    /* Each PR's diagram is a pressed specimen on its own sheet, laid over the
       garden when you pick that plant. :target does the opening, so it stays
       links only — Vimium's f works, and so does the back button. */
    .sheet { display: none; position: fixed; inset: 0; z-index: 10; padding: 5vh 4vw;
             align-items: center; justify-content: center; background: rgba(20,22,23,0.82); }
    .sheet:target { display: flex; }
    .scrim { position: absolute; inset: 0; }
    .sheet article { position: relative; width: min(92vw, 92ch); max-height: 88vh;
                     overflow-y: auto; background: #282828; border: 1px solid #504945;
                     border-radius: 2px; padding: clamp(22px, 2.4vw, 36px); }
    .close { position: absolute; top: 10px; right: 16px; font-size: 26px; line-height: 1;
             color: #928374; text-decoration: none; }
    .close:hover { color: #ebdbb2; }
    .sheet h2 { font-size: 19px; margin: 0 0 6px; font-weight: 600; padding-right: 30px; }
    .sheet h2 a { color: #ebdbb2; text-decoration: none; }
    .sheet h2 a:hover { text-decoration: underline; }
    .sheet h2 .num { font-family: var(--data); font-size: 12px; color: #83a598;
                     letter-spacing: 0.04em; margin-left: 6px; }
    .meta { font-family: var(--data); font-size: 10px; letter-spacing: 0.06em;
            text-transform: uppercase; color: #928374; margin: 0 0 20px; }
    .diagram { background: #232526; border: 1px solid #32302f; border-radius: 2px;
               padding: 18px 20px; margin-bottom: 22px; overflow-x: auto; }
    .diagram svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
    .eyebrow { font-family: var(--data); font-size: 10px; letter-spacing: 0.1em;
               text-transform: uppercase; color: #7c6f64; margin: 0 0 4px;
               padding-bottom: 7px; border-bottom: 1px solid #3c3836; }
    details { border-bottom: 1px solid #32302f; padding: 12px 0 12px 16px;
              border-left: 2px solid transparent; }
    details[open] { border-left-color: #b8bb26; }
    details[open] > summary { color: #fabd2f; }
    summary { cursor: pointer; font-size: 15px; }
    summary:focus { outline: none; }
    summary:focus-visible { text-decoration: underline; }
    .answer { margin: 12px 0 8px; color: #d5c4a1; font-size: 14px; max-width: 66ch; }
    .evidence { margin: 0; padding-left: 16px; list-style: none; }
    .evidence li { font-family: var(--data); font-size: 11.5px; color: #83a598; margin-bottom: 3px; }
    .warn { font-family: var(--data); font-size: 11px; color: #fb4934; margin: 0 0 14px; }
    .empty { color: #928374; padding: 40px 0; }
    @media (prefers-reduced-motion: reduce) { .bloomed .specimen svg { animation: none; } }
  CSS
end

Planted = Data.define(:card, :sheet)

# Every PR gets a stake; only a PR with a diagram gets a sheet. A placeholder sheet
# repeats what its stake already said and costs a screen of scroll, so the ones
# still waiting are counted in a single line instead.
def build_page(prs)
  planted = prs.map { press(it) }

  page(cards: planted.map(&:card).join,
    sheets: planted.filter_map(&:sheet).join,
    waiting: planted.count { it.sheet.nil? })
end

# The stake for the row, and the pressed sheet behind it when there's a diagram to
# press. Rendering the diagram is what decides whether a sheet exists at all.
def press(pr)
  state = pr["status"]
  written = entry(pr["number"]) || {}
  mmd = written.dig("diagram", "mmd")
  svg, error = mmd.to_s.strip.empty? ? [nil, nil] : render_svg(mmd)
  sheet = svg || error

  Planted.new(
    card: plant_card(pr, state:, written:, sheet:),
    sheet: sheet && section_html(pr, state:, written:, svg:,
      warning: warning_html(error, svg ? missing_labels(mmd, svg) : []))
  )
end

def warning_html(error, dropped)
  return "<p class=\"warn\">Diagram failed: #{escape(error)}</p>" if error
  return "" if dropped.empty?

  "<p class=\"warn\">Dropped by the renderer: #{dropped.map { escape(it) }.join(", ")}</p>"
end

def page(cards:, sheets:, waiting:)
  row = cards.empty? ? '<p class="empty">Nothing planted. The garden is clear.</p>' : "<div class=\"row\">#{cards}</div>"
  waiting_line = waiting.positive? ? "<p class=\"waiting\">#{waiting} still to press</p>" : ""

  <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <title>PR Garden</title>
    <style>
    #{styles}
    </style>
    </head>
    <body>
    <h1>PR Garden<span class="when">#{Time.now.strftime("%a %-d %b · %H:%M")}</span></h1>
    #{row}
    #{waiting_line}
    #{sheets}
    <script>
      // :target already opens and closes a sheet; this only adds Escape.
      document.addEventListener("keydown", (event) => {
        if (event.key === "Escape" && location.hash) location.hash = "";
      });
    </script>
    </body>
    </html>
  HTML
end

# What the page is about, so an unchanged tick can stay quiet. Content changes
# only when a PR appears, closes, moves its head commit, or gets rewritten.
def signature(prs)
  prs.map { "#{it["number"]}:#{it["head_sha"]}:#{entry(it["number"])&.dig("generated_at")}" }.sort.join("\n")
end

def report_stale(prs)
  needing, fresh = prs.partition { stale?(it) }
  written = needing.map do |pr|
    pr.slice("number", "title", "handle", "url", "repo", "isDraft", "head_sha", "head_branch")
  end
  puts JSON.pretty_generate({stale: written, fresh: fresh.map { it["number"] }})
end

# The signature depends on nothing the render produces, so check it first: an
# unchanged tick then costs a couple of file reads instead of one node process per
# diagram plus a page rewrite. Ten of these fire every weekday.
def render_page(prs)
  current = signature(prs)
  unchanged = File.exist?(SIGNATURE_PATH) && File.read(SIGNATURE_PATH) == current
  puts PAGE_PATH
  return if unchanged && File.exist?(PAGE_PATH)

  FileUtils.mkdir_p(STUDY_DIR)
  File.write(PAGE_PATH, build_page(prs))
  File.write(SIGNATURE_PATH, current)
  system("open", PAGE_PATH) unless ARGV.include?("--no-open")
end

if __FILE__ == $PROGRAM_NAME
  prs = open_prs
  ARGV.include?("--stale") ? report_stale(prs) : render_page(prs)
end
