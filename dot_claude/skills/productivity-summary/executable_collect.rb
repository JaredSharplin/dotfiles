#!/usr/bin/env ruby
# frozen_string_literal: true

# Collects a productivity snapshot (git + GitHub + Claude session activity) since
# the last checkpoint, appends it to today's JSONL log, and prints it as JSON.
# The tick skill (/productivity-summary) reads stdout to narrate; the recording
# never depends on Claude being accurate.

require "json"
require "time"
require "fileutils"

HOME = Dir.home
DATA_DIR = File.join(HOME, ".local", "share", "productivity")
PROJECTS_DIR = File.join(HOME, ".claude", "projects")
REPOS = [File.join(HOME, "programming", "payaus")] +
        Dir.glob(File.join(HOME, "programming", "worktrees", "*")).select { File.directory?(it) }

def log_path(date) = File.join(DATA_DIR, "#{date}.jsonl")

def git(dir, *args) = IO.popen(["git", "-C", dir, *args], err: File::NULL, &:read)

def gh_json(*args)
  out = IO.popen(["gh", *args], err: File::NULL, &:read)
  out.strip.empty? ? [] : JSON.parse(out)
rescue Errno::ENOENT, JSON::ParserError
  []
end

def git_activity(dir, since)
  return nil unless File.exist?(File.join(dir, ".git"))

  since_arg = since.iso8601
  commits = git(dir, "log", "--since=#{since_arg}", "--oneline").lines.size
  return nil if commits.zero?

  insertions = deletions = 0
  git(dir, "log", "--since=#{since_arg}", "--numstat", "--pretty=tformat:").each_line do |line|
    added, removed, = line.split("\t")
    insertions += added.to_i
    deletions += removed.to_i
  end

  {
    repo: File.basename(dir),
    branch: git(dir, "rev-parse", "--abbrev-ref", "HEAD").strip,
    count: commits,
    insertions:,
    deletions:
  }
end

# Labels that mean the PR ships something to customers. Everything else
# (not-user-facing, refactor, api-only, security tooling) is supporting work.
CUSTOMER_LABELS = %w[feature bug].freeze

def github_activity(since)
  since_arg = since.utc.iso8601
  merged = gh_json("search", "prs", "--author=@me", "--merged-at", ">=#{since_arg}", "--limit", "40",
                   "--json", "number,title,url,labels")
  in_flight = gh_json("search", "prs", "--author=@me", "--state", "open", "--updated", ">=#{since_arg}",
                      "--limit", "40", "--json", "number,title,url,isDraft")
  reviewed = gh_json("search", "prs", "--reviewed-by=@me", "--updated", ">=#{since_arg}", "--limit", "40",
                     "--json", "number,title,url,repository")
  {
    shipped: merged.map do |pr|
      labels = Array(pr["labels"]).map { it["name"] }
      { number: pr["number"], title: pr["title"], url: pr["url"], labels:,
        customer_facing: labels.intersect?(CUSTOMER_LABELS) }
    end,
    in_flight: in_flight.map { it.slice("number", "title", "url", "isDraft") },
    reviews_given: reviewed.map { { number: it["number"], title: it["title"], repo: it.dig("repository", "name") } }
  }
end

def session_activity(checkpoint)
  by_session = Hash.new do |hash, key|
    hash[key] = { user: 0, assistant: 0, tools: Hash.new(0), cwd: nil, branch: nil, title: nil }
  end

  Dir.glob(File.join(PROJECTS_DIR, "*", "*.jsonl")).each do |file|
    next if File.mtime(file) < checkpoint

    File.foreach(file) do |line|
      entry = JSON.parse(line) rescue next
      session_id = entry["sessionId"]
      next unless session_id

      if entry["type"] == "ai-title"
        by_session[session_id][:title] = entry["aiTitle"]
        next
      end

      timestamp = entry["timestamp"]
      next unless timestamp && Time.iso8601(timestamp) >= checkpoint

      session = by_session[session_id]
      session[:cwd] ||= entry["cwd"]
      session[:branch] ||= entry["gitBranch"]

      case entry["type"]
      when "user"
        session[:user] += 1
      when "assistant"
        session[:assistant] += 1
        Array(entry.dig("message", "content")).each do |block|
          next unless block.is_a?(Hash) && block["type"] == "tool_use"

          session[:tools][block["name"]] += 1
        end
      end
    end
  end

  active = by_session.values.select { it[:user] + it[:assistant] > 0 && it[:cwd] }
  active.group_by { it[:cwd] }.map do |cwd, sessions|
    tools = sessions.each_with_object(Hash.new(0)) do |session, acc|
      session[:tools].each { |name, count| acc[name] += count }
    end
    assistant_turns = sessions.sum { it[:assistant] }
    edits = tools.values_at("Edit", "Write", "NotebookEdit", "Bash").sum

    {
      cwd:,
      branch: sessions.first[:branch],
      titles: sessions.filter_map { it[:title] }.uniq,
      user_turns: sessions.sum { it[:user] },
      assistant_turns:,
      tool_calls: tools,
      advancing: assistant_turns.positive? && edits.positive?
    }
  end.sort_by { -it[:assistant_turns] }
end

now = Time.now
today = now.strftime("%Y-%m-%d")
FileUtils.mkdir_p(DATA_DIR)

previous = File.exist?(log_path(today)) ? File.readlines(log_path(today)).last&.then { JSON.parse(it) } : nil
checkpoint =
  if previous
    Time.iso8601(previous["ts"])
  else
    Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)
  end

commits = REPOS.filter_map { git_activity(it, checkpoint) }
github = github_activity(checkpoint)

# A PR that flipped draft -> ready since last tick has cleared the developer's
# manual QA gate — the visible outcome of otherwise-invisible QA work.
previously_draft = Array(previous&.dig("github", "in_flight")).select { it["isDraft"] }.map { it["number"] }
github[:qa_completed] = github[:in_flight].reject { it["isDraft"] }.select { previously_draft.include?(it["number"]) }

record = {
  ts: now.utc.iso8601,
  since: checkpoint.utc.iso8601,
  window: "#{checkpoint.localtime.strftime('%H:%M')}–#{now.localtime.strftime('%H:%M')}",
  git: { commits:, total_commits: commits.sum { it[:count] } },
  github:,
  sessions: session_activity(checkpoint)
}

File.open(log_path(today), "a") { it.puts(JSON.generate(record)) }
puts JSON.pretty_generate(record)
