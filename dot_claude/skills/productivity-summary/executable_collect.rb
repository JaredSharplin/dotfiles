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
# The first tick of the day floors its window here instead of midnight, so it
# reports the workday — not a dump of everything since 00:00. Also the start of
# the working day used to age PRs (see working_days_between).
DAY_START_HOUR = 9
WORK_DAY_END_HOUR = 18
# Working days without a commit before a ready, green PR counts as settled — the
# QA fixes have stopped and the work is genuinely done. Half a working day.
SETTLED_QUIET_DAYS = 0.5

def log_path(date) = File.join(DATA_DIR, "#{date}.jsonl")

def git(dir, *args) = IO.popen(["git", "-C", dir, *args], err: File::NULL, &:read)

def gh_json(*args)
  out = IO.popen(["gh", *args], err: File::NULL, &:read)
  out.strip.empty? ? [] : JSON.parse(out)
rescue Errno::ENOENT, JSON::ParserError
  []
end

def gh_text(*args)
  IO.popen(["gh", *args], err: File::NULL, &:read).strip
rescue Errno::ENOENT
  ""
end

# Everything one checked-out repo contributes to a tick: its branch, when the user
# last committed to it at all, and the commits inside the window. `last_commit_at`
# is deliberately unbounded by the window — it's how long a PR has been quiet, and
# it comes from local git because this developer commits far more often than they
# push, so a PR's last pushed commit can be a day behind the real work.
# Only commits the user authored: a master merge brings other people's recent
# commits into the branch, and --since alone would count them as progress.
def repo_state(dir, since)
  return nil unless File.exist?(File.join(dir, ".git"))

  author = git(dir, "config", "user.email").strip
  return nil if author.empty?

  mine = ["--no-merges", "--author=#{author}"]
  state = {
    repo: File.basename(dir),
    branch: git(dir, "rev-parse", "--abbrev-ref", "HEAD").strip,
    last_commit_at: git(dir, "log", "-1", *mine, "--format=%cI").strip.then { it.empty? ? nil : it }
  }

  windowed = [*mine, "--since=#{since.iso8601}"]
  count = git(dir, "log", *windowed, "--oneline").lines.size
  return state.merge(count: 0) if count.zero?

  insertions = deletions = 0
  git(dir, "log", *windowed, "--numstat", "--pretty=tformat:").each_line do |line|
    added, removed, = line.split("\t")
    insertions += added.to_i
    deletions += removed.to_i
  end

  state.merge(count:, insertions:, deletions:)
end

# Labels that mean the PR ships something to customers. Everything else
# (not-user-facing, refactor, api-only, security tooling) is supporting work.
CUSTOMER_LABELS = %w[feature bug].freeze
# The label that marks a PR intentionally on hold (customer feedback, flag
# rollout). The collector reads it back so the summary stops nagging about it.
ON_HOLD_LABEL = "on-hold"
REVIEW_EVENTS = %w[PullRequestReviewEvent PullRequestReviewCommentEvent].freeze
# GitHub's reviewDecision translated to the words the summary speaks. An empty
# decision (a draft, or a repo without a review policy) maps to nil — not
# applicable — so the summary only talks about review state on ready PRs.
REVIEW_STATES = {
  "APPROVED" => "approved",
  "CHANGES_REQUESTED" => "changes_requested",
  "REVIEW_REQUIRED" => "awaiting_review"
}.freeze
# statusCheckRollup check tokens collapsed to one build state (see build_state):
# any failing check wins, then any still-running check, then a real pass. Marking
# a PR ready only starts CI — a ready PR isn't review-ready until its build passes.
BUILD_FAILING = %w[FAILURE ERROR TIMED_OUT ACTION_REQUIRED STARTUP_FAILURE].freeze
BUILD_PENDING = %w[PENDING EXPECTED QUEUED IN_PROGRESS].freeze

# PRs I reviewed during the window, from my GitHub event feed. The feed carries
# each event's real timestamp (when I actually reviewed), unlike a PR search on
# --updated, which resurfaces any old review the moment someone else touches the PR.
def reviews_given(since)
  login = gh_text("api", "user", "--jq", ".login")
  return [] if login.empty?

  since_utc = since.utc
  events = gh_json("api", "/users/#{login}/events?per_page=100").select do |event|
    REVIEW_EVENTS.include?(event["type"]) && Time.iso8601(event["created_at"]) >= since_utc
  end

  events.group_by { it.dig("payload", "pull_request", "number") }.filter_map do |number, grouped|
    next unless number

    { number:, repo: grouped.first.dig("repo", "name"),
      comments: grouped.count { it["type"] == "PullRequestReviewCommentEvent" } }
  end
end

# Elapsed working time between an ISO timestamp and now, in working days (weekday
# 09:00–18:00 local, 9h each). Time outside those hours — nights, weekends —
# doesn't count, so a PR that's only sat overnight doesn't read as an aged stall.
def working_days_between(iso, now)
  return nil unless iso

  start = Time.iso8601(iso).localtime
  work_hours = WORK_DAY_END_HOUR - DAY_START_HOUR
  hours = 0.0
  day = Time.new(start.year, start.month, start.day, DAY_START_HOUR, 0, 0, start.utc_offset)
  while day < now
    if (1..5).cover?(day.wday)
      open_time = [start, day].max
      close_time = [now, day + work_hours * 3600].min
      hours += (close_time - open_time) / 3600.0 if close_time > open_time
    end
    day += 86_400
  end
  (hours / work_hours).round(1)
end

def label_names(pr) = Array(pr["labels"]).map { it["name"] }

# One PR's statusCheckRollup reduced to passing / pending / failing / none. An
# empty rollup (a draft, or a ready PR whose CI hasn't reported yet) is "none".
def build_state(rollup)
  tokens = Array(rollup).filter_map { |check| [check["conclusion"], check["state"], check["status"]].find { !it.to_s.empty? } }
  return "none" if tokens.empty?
  return "failing" if tokens.any? { BUILD_FAILING.include?(it) }
  return "pending" if tokens.any? { BUILD_PENDING.include?(it) }

  tokens.include?("SUCCESS") ? "passing" : "none"
end

# One gh call per repo fetching every open authored PR with the fields that both
# stack detection and review state need. gh search prs returns neither branch
# refs nor reviewDecision, so we pull them here and share the result.
def open_pr_details(open_prs)
  repos = open_prs.filter_map { it.dig("repository", "nameWithOwner") }.uniq
  repos.flat_map do |repo|
    gh_json("pr", "list", "--repo", repo, "--author", "@me", "--state", "open",
            "--json", "number,headRefName,headRefOid,baseRefName,reviewDecision,statusCheckRollup,commits")
  end
end

# Rebuilds git-town stacks from GitHub branch refs. A PR's base branch is its
# parent's head branch (git town sets --base <parent> when it creates the PR),
# so head->base edges reconstruct the tree. A PR whose base is no other open PR's
# head targets the trunk and is a stack base. Returns [stacks, base_by_number]
# where a stack is a base with at least one child; standalone PRs are omitted.
def pr_stacks(refs)
  return [[], {}] if refs.empty?

  head_to_number = refs.to_h { [it["headRefName"], it["number"]] }
  parent_of = refs.to_h { |pr| [pr["number"], head_to_number[pr["baseRefName"]]] }
  children = refs.map { it["number"] }.group_by { parent_of[it] }

  root_of = lambda do |number|
    number = parent_of[number] while parent_of[number]
    number
  end
  order_from = lambda do |base|
    ordered = []
    queue = [base]
    until queue.empty?
      current = queue.shift
      ordered << current
      queue.concat((children[current] || []).sort)
    end
    ordered
  end

  grouped = refs.map { it["number"] }.group_by { root_of.call(it) }.select { |_base, members| members.size > 1 }
  stacks = grouped.keys.map { { base: it, members: order_from.call(it) } }
  base_by_number = grouped.flat_map { |base, members| members.map { [it, base] } }.to_h
  [stacks, base_by_number]
end

def github_activity(since, now)
  merged = gh_json("search", "prs", "--author=@me", "--merged-at", ">=#{since.utc.iso8601}", "--limit", "40",
                   "--json", "number,title,url,labels")
  open_prs = gh_json("search", "prs", "--author=@me", "--state", "open", "--limit", "40",
                     "--json", "number,title,url,isDraft,createdAt,updatedAt,labels,repository")
  refs = open_pr_details(open_prs)
  stacks, base_by_number = pr_stacks(refs)
  review_by_number = refs.to_h { [it["number"], REVIEW_STATES[it["reviewDecision"]]] }
  build_by_number = refs.to_h { [it["number"], build_state(it["statusCheckRollup"])] }
  head_by_number = refs.to_h { [it["number"], it["headRefName"]] }
  head_sha_by_number = refs.to_h { [it["number"], it["headRefOid"]] }
  pushed_commit_by_number = refs.to_h { [it["number"], Array(it["commits"]).filter_map { it["committedDate"] }.max] }
  {
    shipped: merged.map do |pr|
      labels = label_names(pr)
      { number: pr["number"], title: pr["title"], url: pr["url"], labels:,
        customer_facing: labels.intersect?(CUSTOMER_LABELS) }
    end,
    in_flight: open_prs.map do |pr|
      labels = label_names(pr)
      { number: pr["number"], title: pr["title"], url: pr["url"], repo: pr.dig("repository", "nameWithOwner"),
        isDraft: pr["isDraft"], labels:,
        age_days: working_days_between(pr["createdAt"], now),
        idle_days: working_days_between(pr["updatedAt"], now),
        on_hold: labels.include?(ON_HOLD_LABEL),
        review_state: review_by_number[pr["number"]],
        build_state: build_by_number[pr["number"]],
        head_branch: head_by_number[pr["number"]],
        head_sha: head_sha_by_number[pr["number"]],
        pushed_commit_at: pushed_commit_by_number[pr["number"]],
        stack_base: base_by_number[pr["number"]] }
    end,
    stacks:,
    reviews_given: reviews_given(since)
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
  elsif now.hour >= DAY_START_HOUR
    Time.new(now.year, now.month, now.day, DAY_START_HOUR, 0, 0, now.utc_offset)
  else
    Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)
  end

repo_states = REPOS.filter_map { repo_state(it, checkpoint) }
commits = repo_states.select { it[:count].positive? }.map { it.except(:last_commit_at) }
last_commit_by_branch = repo_states.filter_map { [it[:branch], it[:last_commit_at]] if it[:last_commit_at] }.to_h
github = github_activity(checkpoint, now)

# The previous record is parsed JSON (string keys); this tick's in_flight is
# symbol-keyed, so the two sides read their keys differently.
previous_flight = Array(previous&.dig("github", "in_flight")).to_h { [it["number"], it] }

# A PR that flipped draft -> ready since last tick. For this developer that means
# CI was started (drafts run no CI), not that review is wanted — the build state
# tells the real story.
github[:started_ci] = github[:in_flight]
                      .reject { it[:isDraft] }
                      .select { previous_flight[it[:number]]&.fetch("isDraft", false) }

# The work this period joined onto the PR it went into, so a PR line can show the
# effort going in rather than reading as untouched. Matched on branch name — a
# worktree directory name doesn't map to a GitHub repo, the head ref does.
commits_by_branch = commits.to_h { [it[:branch], it] }
github[:in_flight].each do |pr|
  work = commits_by_branch[pr[:head_branch]]
  pr[:work_this_period] = work&.slice(:count, :insertions, :deletions)

  # Rounds of fixes that landed while the PR was already ready with a green build
  # — QA finding real problems after CI passed. One round is ordinary. A count
  # that keeps climbing means the change isn't holding up, which is worth saying.
  # Back to draft resets it: that's work resuming before CI, not a fix on green.
  was = previous_flight[pr[:number]]
  carried = was ? was.fetch("qa_rounds", 0).to_i : 0
  landed_on_green = pr[:work_this_period] && was && !was["isDraft"] && was["build_state"] == "passing"
  pr[:qa_rounds] = pr[:isDraft] ? 0 : carried + (landed_on_green ? 1 : 0)

  # How long since the developer last committed to this PR, in working days. The
  # local commit usually leads the pushed one (they commit far more than they push),
  # so take whichever is later.
  last_commit = [last_commit_by_branch[pr[:head_branch]], pr[:pushed_commit_at]].compact.max
  pr[:quiet_days] = working_days_between(last_commit, now)

  # A ready PR whose build passes and whose commits have stopped. Marking a PR
  # ready only starts CI; QA then turns up real problems and more commits land.
  # When those stop, the work is actually finished — that, not the ready flip and
  # not GitHub's reviewDecision, is what means a PR is ready for someone else.
  pr[:settled] = !pr[:isDraft] && pr[:build_state] == "passing" &&
                 pr[:quiet_days].to_f >= SETTLED_QUIET_DAYS
end

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
