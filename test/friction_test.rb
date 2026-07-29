#!/usr/bin/env ruby
# frozen_string_literal: true

# Pinned before anything reads the clock: the day window is local-time, and the
# fixture's UTC timestamps only straddle midnight correctly at +10.
ENV["TZ"] = "Australia/Brisbane"

require "minitest/autorun"
require "tmpdir"
require "json"
require_relative "../dot_claude/skills/productivity-summary/executable_friction"

class FrictionTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/friction_transcript.jsonl", __dir__)
  DAY_START = Time.new(2026, 7, 27, 0, 0, 0)
  WINDOW = DAY_START...(DAY_START + 86_400)

  def entries = @entries ||= Friction.entries(path: FIXTURE, lines: File.readlines(FIXTURE), window: WINDOW)

  def markers = @markers ||= Friction.markers(entries)

  def marker_at(uuid) = markers.find { it[:pointer][:uuid] == uuid }

  def test_entries_drop_out_of_window_sidechain_and_unparseable_lines
    expected = %w[p1u a1 u1 a2 u2 a3 a3b u3 u4 a4 u5 a5 u6 u7 b1 v1 u10]

    assert_equal expected, entries.map { it["uuid"] }
  end

  def test_marker_counts_by_kind
    counts = markers.group_by { it[:kind] }.transform_values(&:size)

    assert_equal({ "rejection" => 3, "feedback" => 1, "interrupt" => 1, "correction" => 2, "repeat_failure" => 1 }, counts)
  end

  def test_boilerplate_feedback_is_excluded_and_the_real_one_kept
    feedback = markers.select { it[:kind] == "feedback" }

    assert_equal ["no migrations. that is way out of scope"], feedback.map { it[:text] }
  end

  def test_rejection_resolves_tool_and_skill_through_the_assistant_turn
    rejection = markers.find { it[:pointer][:uuid] == "u1" && it[:kind] == "rejection" }

    assert_equal "Bash", rejection[:tool]
    assert_equal "git-town", rejection[:skill]
    assert_equal "git town sync --push", rejection[:sample]
    assert_equal FIXTURE, rejection[:pointer][:file]
  end

  # The turn Claude was mid-way through when interrupted is often prose, so the
  # tool call that provoked the interrupt sits further up the parent chain.
  def test_interrupt_walks_past_a_prose_turn_to_reach_the_tool_call
    interrupt = marker_at("u3")

    assert_equal "Bash", interrupt[:tool]
    assert_equal "gh pr", interrupt[:signature]
    assert_equal "git-town", interrupt[:skill]
  end

  # A correction names what Claude was doing when it landed. That's what turns a
  # flat pile of corrections into "the ones that followed a `gh pr` call".
  def test_correction_names_the_work_in_flight_when_it_landed
    correction = marker_at("u4")

    assert_equal "correction", correction[:kind]
    assert_equal "git-town", correction[:skill]
    assert_equal "gh pr", correction[:signature]
  end

  # Most friction happens outside any skill. Attribution climbs a bounded parent
  # chain, so a turn with no skill above it honestly reports none.
  def test_skill_is_nil_when_no_skill_ran_above_the_marker
    correction = marker_at("u10")

    assert_nil correction[:skill]
    assert_nil correction[:tool]
  end

  def test_repeat_failure_fires_once_on_the_second_consecutive_error
    repeat = markers.select { it[:kind] == "repeat_failure" }

    assert_equal ["u6"], repeat.map { it[:pointer][:uuid] }
    assert_equal "write-ruby-tests", repeat.first[:skill]
    assert_equal "bin/rails test", repeat.first[:signature]
  end

  # The signature is what makes a cluster actionable: "chezmoi apply" and
  # "git town" are different problems even though both are Bash.
  def test_signature_collapses_a_command_to_its_first_two_words
    assert_equal "git town", Friction.signature_of(tool: "Bash", sample: "git town sync --push")
    assert_equal "bin/rails test", Friction.signature_of(tool: "Bash", sample: "bin/rails test foo.rb:12")
    assert_equal ".rb", Friction.signature_of(tool: "Edit", sample: "/Users/x/app/models/user.rb")
    assert_equal "git-town", Friction.signature_of(tool: "Skill", sample: "git-town")
    assert_nil Friction.signature_of(tool: "Task", sample: "a" * 41)
    assert_nil Friction.signature_of(tool: "ExitPlanMode", sample: nil)
  end

  def test_sample_falls_back_to_the_first_string_argument
    skill_call = { "type" => "tool_use", "name" => "Skill", "input" => { "skill" => "git-town", "args" => "" } }
    task_call = { "type" => "tool_use", "name" => "Task", "input" => { "prompt" => "review the diff" } }

    assert_equal "git-town", Friction.sample_of(skill_call)
    assert_equal "review the diff", Friction.sample_of(task_call)
    assert_nil Friction.sample_of(nil)
  end

  def test_totals_count_real_user_turns_separately_from_markers
    expected = { user_turns: 4, interrupts: 1, rejections: 3, feedback: 1, corrections: 2, repeat_failures: 1 }

    assert_equal expected, Friction.totals(entries:, markers:)
  end

  def test_clusters_group_by_kind_tool_signature_and_skill_ranked_by_count
    clusters = Friction.clusters(markers:, limit: 10)

    assert_equal ["rejection", "Bash", "git town", "git-town", 2], clusters.first.values_at(:kind, :tool, :signature, :skill, :count)
    assert_equal %w[u1 v1], clusters.first[:pointers].map { it[:uuid] }
    assert_equal ["git town sync --push"], clusters.first[:samples]
    assert_equal 7, clusters.size
  end

  def test_clusters_honour_the_limit
    assert_equal 2, Friction.clusters(markers:, limit: 2).size
  end

  def test_breakdown_by_skill_and_by_worktree_both_account_for_every_marker
    skills = Friction.breakdown(markers:, by: :skill)
    worktrees = Friction.breakdown(markers:, by: :worktree)

    assert_equal [["git-town", 6], [nil, 1], ["write-ruby-tests", 1]], skills.map { it.values_at(:name, :count) }
    assert_equal [["payaus", 7], ["mrr-4-cutover", 1]], worktrees.map { it.values_at(:name, :count) }
    assert_equal({ "rejection" => 3, "feedback" => 1, "interrupt" => 1, "correction" => 1 }, skills.first[:kinds])
  end

  def test_sessions_rank_by_assistant_turns_for_the_prompting_review
    sessions = Friction.sessions(entries:, markers:)

    assert_equal [["S1", 6, 6], ["S2", 1, 1], ["S3", 0, 1]], sessions.map { it.values_at(:session, :turns, :markers) }
    assert_equal "payaus", File.basename(sessions.first[:cwd])
    assert_equal FIXTURE, sessions.first[:file]
  end

  def test_recorded_payload_holds_no_conversation_text
    payload = Friction.record(date: "2026-07-27", totals: Friction.totals(entries:, markers:),
                              skills: Friction.breakdown(markers:, by: :skill),
                              worktrees: Friction.breakdown(markers:, by: :worktree),
                              clusters: Friction.clusters(markers:, limit: 10))
    serialised = JSON.generate(payload)

    refute_includes serialised, "no migrations"
    refute_includes serialised, "I told you"
    refute_includes serialised, "sync --push"
    refute_includes serialised, "uninitialized constant"
    assert_includes serialised, "git-town"
    assert_equal 3, payload[:totals][:rejections]
    assert_equal "u1", payload[:clusters].first[:pointers].first[:uuid]
  end

  def test_trend_reads_prior_days_and_tolerates_missing_ones
    Dir.mktmpdir do |dir|
      write_record(dir, "2026-07-25", interrupts: 14)
      write_record(dir, "2026-07-27", interrupts: 4)

      trend = Friction.trend(dir:, date: "2026-07-27", days: 3)

      assert_equal [["2026-07-25", 14], ["2026-07-27", 4]], trend.map { it.values_at(:date, :interrupts) }
    end
  end

  def test_trend_is_empty_when_nothing_was_ever_recorded
    Dir.mktmpdir { assert_empty Friction.trend(dir: it, date: "2026-07-27", days: 7) }
  end

  private

  def write_record(dir, date, interrupts:)
    payload = { date:, totals: { user_turns: 0, interrupts:, rejections: 0, feedback: 0, corrections: 0, repeat_failures: 0 } }
    File.write(File.join(dir, "#{date}.json"), JSON.generate(payload))
  end
end
