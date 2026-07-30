#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders a plain-text end-of-day reflection from a day's productivity log.
# Usage: report.rb [YYYY-MM-DD]  (defaults to today)

require "json"
require "time"

date = ARGV[0] || Time.now.strftime("%Y-%m-%d")
path = File.join(Dir.home, ".local", "share", "productivity", "#{date}.jsonl")
abort "No productivity log for #{date}" unless File.exist?(path)

records = File.readlines(path).filter_map {
  begin
    JSON.parse(it)
  rescue
    nil
  end
}
abort "Empty productivity log for #{date}" if records.empty?

hours = Hash.new { |hash, key| hash[key] = {shipped: 0, ci: 0, commits: 0, turns: 0} }
worktrees = Hash.new(0)

records.each do |record|
  hour = Time.iso8601(record["ts"]).localtime.hour
  hours[hour][:commits] += record.dig("git", "total_commits").to_i
  hours[hour][:shipped] += Array(record.dig("github", "shipped")).size { it["customer_facing"] }
  hours[hour][:ci] += Array(record.dig("github", "started_ci")).size
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

def unique_prs(records, key) = records.flat_map { Array(it.dig("github", key)) }.uniq { it["number"] }

# Shipping dominates the score: a customer ship most, then starting CI on a PR.
scores = hours.transform_values { it[:shipped] * 10 + it[:ci] * 5 + it[:commits] * 3 + it[:turns] }
max_score = scores.values.max || 0
total_commits = records.sum { it.dig("git", "total_commits").to_i }
shipped = unique_prs(records, "shipped")
customer_shipped = shipped.count { it["customer_facing"] }
ci_started = unique_prs(records, "started_ci")
reviews = unique_prs(records, "reviews_given").size
peak_hour, = scores.max_by { |_hour, score| score }

puts "Productivity report — #{date}"
puts "=" * 46
puts "Ticks recorded : #{records.size}"
puts "Shipped        : #{shipped.size} (#{customer_shipped} customer-facing)"
puts "CI started     : #{ci_started.size}"
puts "Commits        : #{total_commits}"
puts "Reviews given  : #{reviews}"
puts "Peak window    : #{format("%02d:00", peak_hour)}" if peak_hour
puts
shipped.each { puts "  🚢 ##{it["number"]} #{it["title"]}" if it["customer_facing"] }
ci_started.each { puts "  ▶️ ##{it["number"]} #{it["title"]}" }
puts unless customer_shipped.zero? && ci_started.empty?
puts "Activity by hour (ship×10 + CI×5 + commits×3 + turns):"
scores.keys.min.upto(scores.keys.max) do |hour|
  score = scores[hour] || 0
  detail = hours[hour]
  puts format("  %02d:00 %-30s %d  (%ds %dci %dc %dt)", hour, bar(score, max_score), score, detail[:shipped], detail[:ci], detail[:commits], detail[:turns])
end
puts
puts "Focus by worktree (assistant turns):"
worktrees.sort_by { -it.last }.first(10).each do |name, turns|
  puts format("  %-32s %d", name, turns)
end
