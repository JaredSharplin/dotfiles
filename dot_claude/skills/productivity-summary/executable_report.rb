#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders a plain-text end-of-day reflection from a day's productivity log.
# Usage: report.rb [YYYY-MM-DD]  (defaults to today)

require "json"
require "time"

date = ARGV[0] || Time.now.strftime("%Y-%m-%d")
path = File.join(Dir.home, ".local", "share", "productivity", "#{date}.jsonl")
abort "No productivity log for #{date}" unless File.exist?(path)

records = File.readlines(path).filter_map { JSON.parse(it) rescue nil }
abort "Empty productivity log for #{date}" if records.empty?

hours = Hash.new { |hash, key| hash[key] = { commits: 0, turns: 0 } }
worktrees = Hash.new(0)

records.each do |record|
  hour = Time.iso8601(record["ts"]).localtime.hour
  hours[hour][:commits] += record.dig("git", "total_commits").to_i
  Array(record["sessions"]).each do |session|
    turns = session["assistant_turns"].to_i
    hours[hour][:turns] += turns
    worktrees[File.basename(session["cwd"].to_s)] += turns
  end
end

def bar(value, max, width = 30)
  return "" if max.zero?

  "█" * ((value.to_f / max) * width).round
end

scores = hours.transform_values { it[:commits] * 3 + it[:turns] }
max_score = scores.values.max || 0
total_commits = records.sum { it.dig("git", "total_commits").to_i }
latest_github = records.reverse.find { !Array(it.dig("github", "authored")).empty? }&.dig("github") || {}
merged = Array(latest_github["authored"]).count { it["state"].to_s.casecmp?("merged") }
reviews = Array(latest_github["reviewed_by_me"]).size
peak_hour, = scores.max_by { |_hour, score| score }

puts "Productivity report — #{date}"
puts "=" * 46
puts "Ticks recorded : #{records.size}"
puts "Commits        : #{total_commits}"
puts "PRs merged     : #{merged}"
puts "Reviews given  : #{reviews}"
puts "Peak window    : #{format('%02d:00', peak_hour)}" if peak_hour
puts
puts "Activity by hour (commits×3 + assistant turns):"
scores.keys.min.upto(scores.keys.max) do |hour|
  score = scores[hour] || 0
  detail = hours[hour]
  puts format("  %02d:00 %-30s %d  (%dc %dt)", hour, bar(score, max_score), score, detail[:commits], detail[:turns])
end
puts
puts "Focus by worktree (assistant turns):"
worktrees.sort_by { -it.last }.first(10).each do |name, turns|
  puts format("  %-32s %d", name, turns)
end
