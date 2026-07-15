#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders the PR garden: every open PR as a plant that wilts the longer it sits
# untouched, ready PRs in flower, today's merges harvested. Writes a
# self-contained HTML page and opens it in the browser. Pass --no-open to skip
# opening (verification).

require "json"
require "time"
require "cgi"
require "fileutils"

DATA_DIR = File.join(Dir.home, ".local", "share", "productivity")
PAGE_PATH = File.join(DATA_DIR, "garden.html")

def gh_json(*args)
  out = IO.popen(["gh", *args], err: File::NULL, &:read)
  out.strip.empty? ? [] : JSON.parse(out)
rescue Errno::ENOENT, JSON::ParserError
  []
end

def age_label(days)
  return "#{(days * 24).round}h" if days < 1

  hours = ((days % 1) * 24).round
  hours.zero? ? "#{days.floor}d" : "#{days.floor}d #{hours}h"
end

# Continuous wilt styling: the older the draft, the browner, droopier, and
# louder its card. Capped so ancient drafts stay legible.
def draft_card(pr, days)
  emoji = case days
          when 0...1 then "🌱"
          when 1...3 then "🥀"
          else "🍂"
          end
  rotate = [days * 4, 15].min.round(1)
  saturate = [1 - (days * 0.15), 0.3].max.round(2)
  sepia = [days * 0.12, 0.6].min.round(2)
  hue = [100 - (days * 14), 30].max.round
  age_px = (14 + [days * 3, 18].min).round

  <<~HTML
    <a class="card" href="#{pr['url']}" style="background: hsl(#{hue}, 22%, 16%)">
      <div class="plant" style="transform: rotate(#{rotate}deg); filter: saturate(#{saturate}) sepia(#{sepia})">#{emoji}</div>
      <div class="age" style="font-size: #{age_px}px">#{age_label(days)}</div>
      <div class="num">##{pr['number']}</div>
      <div class="title">#{CGI.escapeHTML(pr['title'][0, 60])}</div>
      <div class="state">draft — needs testing</div>
    </a>
  HTML
end

def ready_card(pr)
  <<~HTML
    <a class="card ready" href="#{pr['url']}">
      <div class="plant sway">🌸</div>
      <div class="num">##{pr['number']}</div>
      <div class="title">#{CGI.escapeHTML(pr['title'][0, 60])}</div>
      <div class="state">ready — waiting for review</div>
    </a>
  HTML
end

def harvest_card(pr)
  <<~HTML
    <a class="card harvest" href="#{pr['url']}">
      <div class="plant">🧺</div>
      <div class="num">##{pr['number']}</div>
      <div class="title">#{CGI.escapeHTML(pr['title'][0, 60])}</div>
      <div class="state">merged today</div>
    </a>
  HTML
end

now = Time.now
open_prs = gh_json("search", "prs", "--author=@me", "--state", "open", "--limit", "50",
                   "--json", "number,title,url,isDraft,updatedAt")
midnight = Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)
merged_today = gh_json("search", "prs", "--author=@me", "--merged-at", ">=#{midnight.utc.iso8601}",
                       "--limit", "20", "--json", "number,title,url")

drafts, ready = open_prs.partition { it["isDraft"] }
drafts = drafts
  .map { |pr| [pr, (now - Time.iso8601(pr["updatedAt"])) / 86_400.0] }
  .sort_by { |_pr, days| -days }

beds = drafts.map { |pr, days| draft_card(pr, days) }.join + ready.map { ready_card(it) }.join

html = <<~HTML
  <!DOCTYPE html>
  <html>
  <head>
  <meta charset="utf-8">
  <title>PR Garden</title>
  <style>
    body { margin: 0; font-family: -apple-system, sans-serif;
           background: linear-gradient(#141821 0%, #1d2021 70%, #2a2118 70.5%, #241c14 100%);
           min-height: 100vh; }
    h1 { text-align: center; padding-top: 24px; color: #b8bb26; font-weight: 600; }
    .bed { display: flex; flex-wrap: wrap; gap: 20px; justify-content: center;
           padding: 30px 40px 60px; align-items: flex-end; }
    .card { width: 170px; border-radius: 12px; padding: 16px 12px; text-align: center;
            text-decoration: none; color: #ebdbb2; box-shadow: 0 3px 12px rgba(0,0,0,0.5);
            transition: transform 0.15s; }
    .card:hover { transform: translateY(-4px); }
    .card.ready { background: #32302f; }
    .card.harvest { background: #2c2a24; opacity: 0.9; }
    .plant { font-size: 64px; line-height: 1.2; }
    .sway { display: inline-block; animation: sway 3s ease-in-out infinite; }
    @keyframes sway { 0%, 100% { transform: rotate(-3deg); } 50% { transform: rotate(3deg); } }
    .age { font-weight: 700; color: #fe8019; }
    .num { font-weight: 600; margin-top: 4px; }
    .title { font-size: 12px; margin-top: 4px; min-height: 30px; }
    .state { font-size: 11px; color: #928374; margin-top: 6px; }
    .harvest-row { border-top: 2px dashed #504945; margin: 0 40px; }
    h2 { text-align: center; color: #d79921; font-weight: 600; margin-top: 24px; }
    .empty { text-align: center; color: #a89984; padding: 40px; font-size: 18px; }
  </style>
  </head>
  <body>
  <h1>🌿 PR Garden — #{now.strftime('%a %-d %b, %H:%M')}</h1>
  #{beds.empty? ? '<div class="empty">No open PRs. The garden is clear.</div>' : "<div class=\"bed\">#{beds}</div>"}
  #{unless merged_today.empty?
      "<div class=\"harvest-row\"></div><h2>🧺 Harvested today</h2><div class=\"bed\">#{merged_today.map { harvest_card(it) }.join}</div>"
    end}
  </body>
  </html>
HTML

FileUtils.mkdir_p(DATA_DIR)
File.write(PAGE_PATH, html)
puts PAGE_PATH
system("open", PAGE_PATH) unless ARGV.include?("--no-open")
