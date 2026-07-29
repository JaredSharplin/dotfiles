#!/usr/bin/env ruby
# frozen_string_literal: true

# Finds the turns in a day's Claude transcripts where the work went wrong —
# interrupts, rejected tool calls, corrections — and reduces them to counts plus
# pointers back into the transcript. Runs once a day from /productivity-report,
# which sends subagents down the pointers to read what actually happened.
#
# Usage: friction.rb [YYYY-MM-DD]  (defaults to today)
#
# Everything here is deterministic, same contract as collect.rb: this script
# produces facts, the skill does the talking.

require "json"
require "time"
require "date"
require "fileutils"

module Friction
  PROJECTS_DIR = File.join(Dir.home, ".claude", "projects")
  RECORD_DIR = File.join(Dir.home, ".local", "share", "productivity", "friction")

  INTERRUPT_PREFIX = "[Request interrupted"
  # The harness writes this into userFeedback whenever it asks a clarifying
  # question. It isn't something the developer typed, and left in it crowds out
  # the handful of real ones, which are the best material in the whole corpus.
  BOILERPLATE_FEEDBACK = "The user wants to clarify these questions"
  # The one fuzzy signal here — a regex over prose, so it catches innocent uses of
  # "stop" and "again". Every other marker comes from a first-class transcript
  # field and is exact; the skill is required to report this one as approximate.
  CORRECTION = /\b(no,|nope|i said|i told you|stop|don'?t|why did you|you didn'?t|that'?s wrong|not what)\b/i
  # A denial's tool_result is flagged is_error too, so it would otherwise read as a
  # tool failure. It isn't one — the tool never ran — so denials sit out of the
  # consecutive-failure streak entirely.
  DENIAL_KINDS = %w[user-rejected automode-blocked].freeze

  # How far back up the parent chain to look for the tool call a marker is about.
  # When you interrupt, the turn in flight is often prose and the call that
  # provoked you sits several turns above it; measured over a real day, every
  # interrupt but one resolves within six.
  ANCESTOR_HOPS = 6
  # Rows that are part of the conversation. A transcript also carries attachment,
  # mode and pr-link rows, which sit in the parent chain but aren't turns — they
  # have to be walked through without spending a hop, or the tool call a marker is
  # about disappears behind them.
  CONVERSATION_TYPES = %w[user assistant].freeze
  # Hard stop on the climb. Hops only count conversation rows, so without this a
  # long run of attachment rows — or a parent link that loops — walks forever.
  MAX_ANCESTOR_STEPS = 40
  # Pressing escape on a modal writes a rejection and an interrupt at the same
  # instant. Same keypress, one piece of friction — on 2026-07-28, 16 of 18
  # rejections had an interrupt twinned to them.
  TWIN_SECONDS = 2
  # Longest tool argument still short enough to read as a label rather than content.
  LABEL_LENGTH = 40

  GROUPERS = {
    skill: ->(marker) { marker[:skill] },
    worktree: ->(marker) { File.basename(marker[:cwd].to_s) }
  }.freeze

  # Parsed, in-window, non-subagent turns from one transcript, stamped with the
  # file they came from so a marker can point back at it later.
  def self.entries(path:, lines:, window:)
    lines.filter_map do |line|
      entry = parse(line)
      next unless entry.is_a?(Hash) && !entry["isSidechain"] && entry["timestamp"]

      at = Time.iso8601(entry["timestamp"]).localtime
      next unless window.cover?(at)

      entry.merge(path:, at:)
    end
  end

  def self.markers(entries)
    by_uuid = entries.to_h { [it["uuid"], it] }
    streaks = {}

    entries.flat_map do |entry|
      use = tool_use(ancestor(entry, by_uuid) { tool_use(it) })
      # `use` throughout means what Claude was doing when the marker landed, which
      # holds for a correction as much as a rejection — it's what makes "corrections
      # after a `chezmoi apply`" a group worth reading.
      context = { entry:, use:,
                  skill: entry["attributionSkill"] || ancestor(entry, by_uuid) { it["attributionSkill"] }&.dig("attributionSkill") }

      found = []
      found << marker(kind: "rejection", **context) if DENIAL_KINDS.include?(entry["toolDenialKind"])
      feedback = feedback_text(entry)
      found << marker(kind: "feedback", text: feedback, **context) if feedback
      case user_text(entry)
      in String => text if text.start_with?(INTERRUPT_PREFIX) then found << marker(kind: "interrupt", **context)
      in String => text if typed?(entry) && CORRECTION.match?(text) then found << marker(kind: "correction", **context)
      else nil
      end
      found << marker(kind: "repeat_failure", **context) if repeat_failure?(entry, use&.fetch("name", nil), streaks)
      found
    end.then { drop_twinned_interrupts(it) }
  end

  # A correction is something the developer typed. Slash-command bodies, task
  # notifications and hook output all arrive as `type: "user"` too, and a skill body
  # full of "never", "don't" and "stop" trips the regex on every tick — on
  # 2026-07-28 that accounted for 25 of 49 "corrections" and task notifications for
  # 5 more. Interrupt turns carry no `origin` at all, which is why this guards the
  # correction branch rather than `user_text` itself.
  def self.typed?(entry) = entry.dig("origin", "kind") == "human"

  # One escape keypress on a modal, counted once.
  def self.drop_twinned_interrupts(markers)
    rejections = markers.select { it[:kind] == "rejection" }
    markers.reject do |marker|
      marker[:kind] == "interrupt" &&
        rejections.any? { it[:session] == marker[:session] && (it[:at] - marker[:at]).abs <= TWIN_SECONDS }
    end
  end

  def self.parse(line)
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end

  # Climbs the parent chain from a marker's turn looking for one the block accepts.
  # Both things a marker needs sit above it rather than on it: the tool call it is
  # about, and the skill that was running. A rejection links straight to the
  # assistant turn via sourceToolAssistantUUID; everything else walks parentUuid.
  # The hop cap is what keeps attribution honest — beyond the immediate exchange,
  # a skill that ran earlier in the session isn't to blame for this turn.
  def self.ancestor(entry, by_uuid)
    current = by_uuid[entry["sourceToolAssistantUUID"] || entry["parentUuid"]]
    hops = 0
    steps = 0
    while current && hops < ANCESTOR_HOPS && steps < MAX_ANCESTOR_STEPS
      return current if yield(current)

      hops += 1 if CONVERSATION_TYPES.include?(current["type"])
      steps += 1
      current = by_uuid[current["parentUuid"]]
    end
    nil
  end

  def self.tool_use(entry) = blocks(entry).find { it["type"] == "tool_use" }

  def self.blocks(entry) = Array(entry&.dig("message", "content")).select { it.is_a?(Hash) }

  def self.marker(kind:, entry:, use:, skill:, text: nil)
    tool = use&.fetch("name", nil)
    sample = sample_of(use)
    { kind:, skill:, text:, tool:, sample:, signature: signature_of(tool:, sample:), at: entry[:at],
      cwd: entry["cwd"], branch: entry["gitBranch"], session: entry["sessionId"],
      pointer: { file: entry[:path], uuid: entry["uuid"] } }
  end

  # What a cluster is really about. Grouping on the tool alone is too coarse to act
  # on — "33 interrupts on Bash" names no problem, while "12 interrupts on `chezmoi
  # apply`" names one. A command collapses to its first two words, a file to its
  # extension.
  def self.signature_of(tool:, sample:)
    return nil unless sample

    case tool
    when "Bash" then sample.split(/\s+/).first(2).join(" ")
    when "Read", "Edit", "Write", "NotebookEdit" then File.extname(sample).then { it.empty? ? nil : it }
    # A short argument is already a label — a Skill call's skill name, say. A long
    # one is content, and content doesn't group.
    else sample.length <= LABEL_LENGTH ? sample : nil
    end
  end

  # A one-line handle for what the tool was about to do — enough to cluster and to
  # recognise in a report, never the full input.
  def self.sample_of(use)
    input = use&.fetch("input", nil)
    return nil unless input.is_a?(Hash)

    named = input.values_at("command", "file_path", "pattern", "url", "skill").compact.first
    # Anything else falls back to its first string argument, which is what makes a
    # Skill or Task call cluster by what it invoked rather than vanishing into nil.
    (named || input.values.find { it.is_a?(String) && !it.empty? })&.slice(0, 120)
  end

  def self.user_text(entry)
    return nil unless entry["type"] == "user"

    content = entry.dig("message", "content")
    return content if content.is_a?(String)

    blocks(entry).select { it["type"] == "text" }.map { it["text"] }.join("\n").then { it.empty? ? nil : it }
  end

  def self.feedback_text(entry)
    text = entry["userFeedback"].to_s.strip
    text.empty? || text.start_with?(BOILERPLATE_FEEDBACK) ? nil : text
  end

  # True on the second and each later failure of the same tool in a row. Mutates
  # the per-session streak as it walks, so it must be called once per entry in
  # transcript order.
  def self.repeat_failure?(entry, tool, streaks)
    return false if DENIAL_KINDS.include?(entry["toolDenialKind"])

    result = blocks(entry).find { it["type"] == "tool_result" }
    return false unless result

    session = entry["sessionId"]
    unless result["is_error"]
      streaks.delete(session)
      return false
    end

    streak = streaks[session]
    streaks[session] = { tool:, count: streak && streak[:tool] == tool ? streak[:count] + 1 : 1 }
    streaks[session][:count] >= 2
  end

  def self.totals(entries:, markers:)
    counts = markers.group_by { it[:kind] }.transform_values(&:size)
    { user_turns: entries.count { real_user_turn?(it) },
      interrupts: counts.fetch("interrupt", 0),
      rejections: counts.fetch("rejection", 0),
      feedback: counts.fetch("feedback", 0),
      corrections: counts.fetch("correction", 0),
      repeat_failures: counts.fetch("repeat_failure", 0) }
  end

  def self.real_user_turn?(entry)
    return false unless typed?(entry)

    text = user_text(entry)
    !text.nil? && !text.start_with?(INTERRUPT_PREFIX)
  end

  def self.clusters(markers:, limit:)
    markers.group_by { it.values_at(:kind, :tool, :signature, :skill) }
           .map do |(kind, tool, signature, skill), group|
             { kind:, tool:, signature:, skill:, count: group.size,
               samples: group.filter_map { it[:sample] }.uniq.first(3),
               pointers: group.map { it[:pointer] } }
           end
           .sort_by { [-it[:count], it[:kind], it[:tool].to_s, it[:signature].to_s] }
           .first(limit)
  end

  def self.breakdown(markers:, by:)
    markers.group_by(&GROUPERS.fetch(by))
           .map { |name, group| { name:, count: group.size, kinds: group.group_by { it[:kind] }.transform_values(&:size) } }
           .sort_by { [-it[:count], it[:name].to_s] }
  end

  # The day's sessions ranked by how much work went through them. The busiest are
  # the ones worth reading end to end for how they were driven, which friction
  # markers alone can't show.
  def self.sessions(entries:, markers:)
    marker_counts = markers.group_by { it[:session] }.transform_values(&:size)
    entries.group_by { it["sessionId"] }
           .map do |session, group|
             { session:, cwd: group.filter_map { it["cwd"] }.first, branch: group.filter_map { it["gitBranch"] }.first,
               file: group.first[:path],
               turns: group.count { it["type"] == "assistant" }, markers: marker_counts.fetch(session, 0) }
           end
           .sort_by { [-it[:turns], it[:session].to_s] }
  end

  # What gets kept on disk: counts, skill and tool names, and pointers. No
  # conversation text ever — the samples and feedback stay in stdout only.
  def self.record(date:, totals:, skills:, worktrees:, clusters:)
    { date:, totals:, skills:, worktrees:,
      clusters: clusters.map { it.slice(:kind, :tool, :signature, :skill, :count, :pointers) } }
  end

  def self.trend(dir:, date:, days:)
    last = Date.parse(date)
    ((last - days + 1)..last).filter_map do |day|
      path = File.join(dir, "#{day}.json")
      next unless File.exist?(path)

      { date: day.to_s, **JSON.parse(File.read(path), symbolize_names: true).fetch(:totals, {}) }
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  date = ARGV[0] || Time.now.strftime("%Y-%m-%d")
  day = Date.parse(date)
  start = Time.new(day.year, day.month, day.day, 0, 0, 0)
  window = start...(start + 86_400)

  # A file untouched since the day began can hold nothing from that day, so skip it
  # without reading — the corpus is hundreds of megabytes.
  entries = Dir.glob(File.join(Friction::PROJECTS_DIR, "*", "*.jsonl"))
               .reject { File.mtime(it) < start }
               .flat_map { Friction.entries(path: it, lines: File.readlines(it), window:) }
  # Safe across files in one call: every piece of state markers tracks is keyed by
  # session, and a session never spans two transcripts.
  markers = Friction.markers(entries)

  totals = Friction.totals(entries:, markers:)
  skills = Friction.breakdown(markers:, by: :skill)
  worktrees = Friction.breakdown(markers:, by: :worktree)
  clusters = Friction.clusters(markers:, limit: 6)

  FileUtils.mkdir_p(Friction::RECORD_DIR)
  record = Friction.record(date:, totals:, skills:, worktrees:, clusters:)
  File.write(File.join(Friction::RECORD_DIR, "#{date}.json"), JSON.generate(record))

  puts JSON.pretty_generate(
    date:, totals:, skills:, worktrees:, clusters:,
    feedback: markers.select { it[:kind] == "feedback" }.map { it.slice(:text, :skill, :tool, :pointer) },
    sessions: Friction.sessions(entries:, markers:).first(5),
    trend: Friction.trend(dir: Friction::RECORD_DIR, date:, days: 7)
  )
end
