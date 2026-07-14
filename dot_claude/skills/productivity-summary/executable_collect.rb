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

def github_activity(today)
  authored = gh_json("search", "prs", "--author=@me", "--updated=>=#{today}", "--limit", "40",
                     "--json", "number,title,state,url,isDraft")
  reviewed = gh_json("search", "prs", "--reviewed-by=@me", "--updated=>=#{today}", "--limit", "40",
                     "--json", "number,title,url,repository")
  {
    authored:,
    reviewed_by_me: reviewed.map { { number: it["number"], title: it["title"], url: it["url"], repo: it.dig("repository", "name") } }
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

checkpoint =
  if File.exist?(log_path(today)) && (last = File.readlines(log_path(today)).last)
    Time.iso8601(JSON.parse(last)["ts"])
  else
    Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)
  end

commits = REPOS.filter_map { git_activity(it, checkpoint) }

record = {
  ts: now.utc.iso8601,
  since: checkpoint.utc.iso8601,
  git: { commits:, total_commits: commits.sum { it[:count] } },
  github: github_activity(today),
  sessions: session_activity(checkpoint)
}

File.open(log_path(today), "a") { it.puts(JSON.generate(record)) }
puts JSON.pretty_generate(record)
