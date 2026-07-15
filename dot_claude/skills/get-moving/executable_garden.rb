#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders the PR garden: every open PR as a plant that wilts the longer it sits
# untouched, ready PRs in flower, today's merges harvested. Clicking a plant
# shows its care card — the saved first step and reading list from /get-moving
# (~/.local/share/productivity/jumplists/<pr>.json) — or a hint to grow one.
# Writes a self-contained HTML page and opens it in the browser.
#
# Usage: garden.rb [--target <pr-number>] [--no-open]
#   --target  highlight that plant and show its care card on load
#   --no-open write the page without opening the browser (the page refreshes
#             itself every 30s, so an open tab picks up a re-render)

require "json"
require "time"
require "cgi"
require "fileutils"

DATA_DIR = File.join(Dir.home, ".local", "share", "productivity")
JUMPLIST_DIR = File.join(DATA_DIR, "jumplists")
PAGE_PATH = File.join(DATA_DIR, "garden.html")

def gh_json(*args)
  out = IO.popen(["gh", *args], err: File::NULL, &:read)
  out.strip.empty? ? [] : JSON.parse(out)
rescue Errno::ENOENT, JSON::ParserError
  []
end

def age_label(days)
  return "#{(days * 24).round}h" if days < 1

  "#{days.round}d"
end

def jumplists
  @jumplists ||= Dir.glob(File.join(JUMPLIST_DIR, "*.json")).to_h do |file|
    data = JSON.parse(File.read(file))
    [data["number"], data]
  rescue JSON::ParserError
    [nil, nil]
  end
end

def care_card(number)
  data = jumplists[number]
  unless data
    return "<p class=\"hint\">No care card yet. Type <code>/get-moving #{number}</code> in your terminal to tend this plant.</p>"
  end

  read = Array(data["read"]).map { "<li><code>#{CGI.escapeHTML(it)}</code></li>" }.join
  answer = Array(data["answer"]).map { "<li>#{CGI.escapeHTML(it)}</li>" }.join
  <<~HTML
    <p class="first-step">🪴 <strong>First step:</strong> #{CGI.escapeHTML(data['first_step'].to_s)}</p>
    <div class="cols">
      <div><h3>Read, in order</h3><ol>#{read}</ol></div>
      <div><h3>Answer while reading</h3><ul>#{answer}</ul></div>
    </div>
  HTML
end

# Uniform card shell so every plant sits at the same height regardless of
# state or title length. `meta` is the two dated lines under the plant.
def card(pr, plant:, state:, classes: "", style: "", plant_style: "", meta: "")
  <<~HTML
    <div class="card #{classes}" style="#{style}" onclick="show(#{pr['number']})">
      <div class="plant" style="#{plant_style}">#{plant}</div>
      <div class="meta">#{meta}</div>
      <div class="num">##{pr['number']} <a class="gh" href="#{pr['url']}" onclick="event.stopPropagation()">↗</a></div>
      <div class="title">#{CGI.escapeHTML(pr['title'][0, 80])}</div>
      <div class="state">#{state}</div>
    </div>
    <template id="panel-#{pr['number']}">
      <h2>#{plant} ##{pr['number']} — #{CGI.escapeHTML(pr['title'][0, 80])}</h2>
      #{care_card(pr['number'])}
    </template>
  HTML
end

def draft_card(pr, untouched_days, planted_days, target)
  plant = case untouched_days
          when 0...1 then "🌱"
          when 1...3 then "🥀"
          else "🍂"
          end
  rotate = [untouched_days * 4, 15].min.round(1)
  saturate = [1 - (untouched_days * 0.15), 0.3].max.round(2)
  sepia = [untouched_days * 0.12, 0.6].min.round(2)
  hue = [100 - (untouched_days * 14), 30].max.round
  age_px = (13 + [untouched_days * 3, 10].min).round

  card(pr,
       plant:,
       state: "draft — needs testing",
       classes: pr["number"] == target ? "target" : "",
       style: "background: hsl(#{hue}, 22%, 16%)",
       plant_style: "transform: rotate(#{rotate}deg); filter: saturate(#{saturate}) sepia(#{sepia})",
       meta: "<span class=\"age\" style=\"font-size: #{age_px}px\">untouched #{age_label(untouched_days)}</span>" \
             "<span class=\"planted\">planted #{age_label(planted_days)} ago</span>")
end

def ready_card(pr, untouched_days, planted_days, target)
  card(pr,
       plant: "🌸",
       state: "ready — waiting for review",
       classes: "ready #{'target' if pr['number'] == target}",
       plant_style: "animation: sway 3s ease-in-out infinite",
       meta: "<span class=\"age\">waiting #{age_label(untouched_days)}</span>" \
             "<span class=\"planted\">planted #{age_label(planted_days)} ago</span>")
end

def harvest_card(pr)
  card(pr, plant: "🧺", state: "merged today", classes: "harvest")
end

target = ARGV.include?("--target") ? ARGV[ARGV.index("--target") + 1].to_i : nil
now = Time.now
open_prs = gh_json("search", "prs", "--author=@me", "--state", "open", "--limit", "50",
                   "--json", "number,title,url,isDraft,updatedAt,createdAt")
midnight = Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)
merged_today = gh_json("search", "prs", "--author=@me", "--merged-at", ">=#{midnight.utc.iso8601}",
                       "--limit", "20", "--json", "number,title,url")

days_since = ->(iso) { (now - Time.iso8601(iso)) / 86_400.0 }
drafts, ready = open_prs.partition { it["isDraft"] }
beds = drafts
  .sort_by { -days_since.call(it["updatedAt"]) }
  .map { draft_card(it, days_since.call(it["updatedAt"]), days_since.call(it["createdAt"]), target) }
  .join
beds += ready.map { ready_card(it, days_since.call(it["updatedAt"]), days_since.call(it["createdAt"]), target) }.join

html = <<~HTML
  <!DOCTYPE html>
  <html>
  <head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="30">
  <title>PR Garden</title>
  <style>
    body { margin: 0; font-family: -apple-system, sans-serif; color: #ebdbb2;
           background: linear-gradient(#141821 0%, #1d2021 70%, #2a2118 70.5%, #241c14 100%);
           min-height: 100vh; }
    h1 { text-align: center; padding-top: 24px; color: #b8bb26; font-weight: 600; }
    .bed { display: flex; flex-wrap: wrap; gap: 20px; justify-content: center;
           padding: 30px 40px 40px; align-items: stretch; }
    .card { width: 170px; min-height: 215px; border-radius: 12px; padding: 16px 12px;
            text-align: center; color: #ebdbb2; box-shadow: 0 3px 12px rgba(0,0,0,0.5);
            transition: transform 0.15s; cursor: pointer; background: #262626;
            display: flex; flex-direction: column; justify-content: flex-end; }
    .card:hover { transform: translateY(-4px); }
    .card.ready { background: #32302f; }
    .card.harvest { background: #2c2a24; opacity: 0.9; cursor: default; }
    .card.target { outline: 2px solid #b8bb26; box-shadow: 0 0 18px rgba(184,187,38,0.35); }
    .plant { font-size: 64px; line-height: 1.2; }
    @keyframes sway { 0%, 100% { transform: rotate(-3deg); } 50% { transform: rotate(3deg); } }
    .meta { min-height: 40px; display: flex; flex-direction: column; gap: 2px; margin-top: 6px; }
    .age { font-weight: 700; color: #fe8019; font-size: 13px; }
    .planted { font-size: 11px; color: #a89984; }
    .num { font-weight: 600; margin-top: 4px; }
    .gh { color: #83a598; text-decoration: none; font-size: 13px; }
    .title { font-size: 12px; margin-top: 4px; height: 30px; overflow: hidden;
             display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
    .state { font-size: 11px; color: #928374; margin-top: 6px; }
    .plaque { max-width: 760px; margin: 0 auto 50px; background: #262320; border: 1px solid #504945;
              border-radius: 12px; padding: 20px 28px; display: none; }
    .plaque h2 { color: #d79921; font-size: 17px; margin: 0 0 12px; text-align: left; }
    .plaque h3 { color: #b8bb26; font-size: 13px; margin: 12px 0 6px; }
    .first-step { background: #32302f; border-left: 3px solid #b8bb26; padding: 10px 14px;
                  border-radius: 6px; font-size: 14px; }
    .cols { display: flex; gap: 30px; flex-wrap: wrap; }
    .cols > div { flex: 1; min-width: 280px; }
    .plaque li { font-size: 13px; margin-bottom: 5px; }
    .plaque code { background: #1d2021; padding: 1px 5px; border-radius: 4px; color: #d3869b; }
    .hint { color: #a89984; font-size: 14px; }
    .harvest-row { border-top: 2px dashed #504945; margin: 0 40px; }
    h2.harvest-h { text-align: center; color: #d79921; font-weight: 600; margin-top: 24px; }
    .empty { text-align: center; color: #a89984; padding: 40px; font-size: 18px; }
  </style>
  </head>
  <body>
  <h1>🌿 PR Garden — #{now.strftime('%a %-d %b, %H:%M')}</h1>
  #{beds.empty? ? '<div class="empty">No open PRs. The garden is clear.</div>' : "<div class=\"bed\">#{beds}</div>"}
  <section id="plaque" class="plaque"></section>
  #{unless merged_today.empty?
      "<div class=\"harvest-row\"></div><h2 class=\"harvest-h\">🧺 Harvested today</h2><div class=\"bed\">#{merged_today.map { harvest_card(it) }.join}</div>"
    end}
  <script>
    function show(n) {
      const tpl = document.getElementById('panel-' + n);
      if (!tpl) return;
      const plaque = document.getElementById('plaque');
      plaque.innerHTML = tpl.innerHTML;
      plaque.style.display = 'block';
      localStorage.setItem('garden_sel', n);
      plaque.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
    const initial = #{target || 'null'} || Number(localStorage.getItem('garden_sel'));
    if (initial) show(initial);
  </script>
  </body>
  </html>
HTML

FileUtils.mkdir_p(JUMPLIST_DIR)
File.write(PAGE_PATH, html)
puts PAGE_PATH
system("open", PAGE_PATH) unless ARGV.include?("--no-open")
