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

hours = Hash.new { |hash, key| hash[key] = { shipped: 0, commits: 0, turns: 0 } }
worktrees = Hash.new(0)

records.each do |record|
  hour = Time.iso8601(record["ts"]).localtime.hour
  hours[hour][:commits] += record.dig("git", "total_commits").to_i
  hours[hour][:shipped] += Array(record.dig("github", "shipped")).count { it["customer_facing"] }
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

# A customer-facing ship dominates the score — it's the metric that matters.
scores = hours.transform_values { it[:shipped] * 10 + it[:commits] * 3 + it[:turns] }
max_score = scores.values.max || 0
total_commits = records.sum { it.dig("git", "total_commits").to_i }
shipped = records.flat_map { Array(it.dig("github", "shipped")) }.uniq { it["number"] }
customer_shipped = shipped.count { it["customer_facing"] }
reviews = records.flat_map { Array(it.dig("github", "reviews_given")) }.uniq { it["number"] }.size
peak_hour, = scores.max_by { |_hour, score| score }

puts "Productivity report — #{date}"
puts "=" * 46
puts "Ticks recorded : #{records.size}"
puts "Shipped        : #{shipped.size} (#{customer_shipped} customer-facing)"
puts "Commits        : #{total_commits}"
puts "Reviews given  : #{reviews}"
puts "Peak window    : #{format('%02d:00', peak_hour)}" if peak_hour
puts
shipped.each { puts "  🚢 ##{it['number']} #{it['title']}" if it["customer_facing"] }
puts unless customer_shipped.zero?
puts "Activity by hour (customer ship×10 + commits×3 + assistant turns):"
scores.keys.min.upto(scores.keys.max) do |hour|
  score = scores[hour] || 0
  detail = hours[hour]
  puts format("  %02d:00 %-30s %d  (%ds %dc %dt)", hour, bar(score, max_score), score, detail[:shipped], detail[:commits], detail[:turns])
end
puts
puts "Focus by worktree (assistant turns):"
worktrees.sort_by { -it.last }.first(10).each do |name, turns|
  puts format("  %-32s %d", name, turns)
end
