#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

load File.expand_path("../dot_claude/hooks/executable_spoken-summary.rb", __dir__)

class MessageToSummariseTest < Minitest::Test
  def test_returns_last_assistant_message
    message = SpokenSummary.message_to_summarise(
      hook_input: {"last_assistant_message" => "Fixed the test."}, environment: {}
    )

    assert_equal "Fixed the test.", message
  end

  def test_truncates_long_messages
    message = SpokenSummary.message_to_summarise(
      hook_input: {"last_assistant_message" => "a" * 5000}, environment: {}
    )

    assert_equal "a" * 4000, message
  end

  def test_nil_when_message_is_blank
    message = SpokenSummary.message_to_summarise(
      hook_input: {"last_assistant_message" => "  \n"}, environment: {}
    )

    assert_nil message
  end

  def test_nil_when_message_is_missing
    message = SpokenSummary.message_to_summarise(hook_input: {}, environment: {})

    assert_nil message
  end

  def test_nil_when_stop_hook_is_already_active
    message = SpokenSummary.message_to_summarise(
      hook_input: {"last_assistant_message" => "Fixed the test.", "stop_hook_active" => true}, environment: {}
    )

    assert_nil message
  end

  def test_nil_inside_the_summarising_claude_session
    message = SpokenSummary.message_to_summarise(
      hook_input: {"last_assistant_message" => "Fixed the test."}, environment: {"SPOKEN_SUMMARY_CHILD" => "1"}
    )

    assert_nil message
  end
end

class SpeakableTest < Minitest::Test
  def test_removes_commit_hash_and_its_preposition
    assert_equal "Muted peon-ping and committed it.",
      SpokenSummary.speakable("Muted peon-ping and committed it as 7bfe64d.")
  end

  def test_removes_full_length_commit_hash
    assert_equal "Reverted.",
      SpokenSummary.speakable("Reverted 0123456789abcdef0123456789abcdef01234567.")
  end

  def test_keeps_short_and_comma_grouped_numbers
    assert_equal "Fixed 3 tests across 1234 rows and 12,000 shifts.",
      SpokenSummary.speakable("Fixed 3 tests across 1234 rows and 12,000 shifts.")
  end

  def test_reads_bare_long_number_digit_by_digit
    assert_equal "The review of six five eight seven eight is still running.",
      SpokenSummary.speakable("The review of 65878 is still running.")
  end

  def test_reads_pull_request_number_digit_by_digit
    assert_equal "Opened PR six five six six eight which adds spoken summaries.",
      SpokenSummary.speakable("Opened PR #65668 which adds spoken summaries.")
  end

  def test_shortens_pull_request_to_pr
    assert_equal "Updated PR one two three.",
      SpokenSummary.speakable("Updated pull request 123.")
  end

  def test_keeps_the_article
    assert_equal "Merged the PR four two.",
      SpokenSummary.speakable("Merged the PR #42.")
  end

  def test_reads_hash_number_digit_by_digit
    assert_equal "Closed issue four two.",
      SpokenSummary.speakable("Closed issue #42.")
  end
end

class SessionTitleTest < Minitest::Test
  def with_transcript(*entries)
    Dir.mktmpdir do |directory|
      transcript_path = File.join(directory, "session.jsonl")
      File.write(transcript_path, entries.map(&:to_json).join("\n"))
      yield transcript_path
    end
  end

  def test_latest_custom_title_wins_over_ai_title
    with_transcript(
      {"type" => "custom-title", "customTitle" => "Old name"},
      {"type" => "custom-title", "customTitle" => "AI Enablement: Code Review"},
      {"type" => "ai-title", "aiTitle" => "ai code review handoff"}
    ) do |transcript_path|
      assert_equal "AI Enablement: Code Review", SpokenSummary.session_title(transcript_path:)
    end
  end

  def test_falls_back_to_latest_ai_title
    with_transcript(
      {"type" => "ai-title", "aiTitle" => "first guess"},
      {"type" => "user", "message" => {"content" => "hello"}},
      {"type" => "ai-title", "aiTitle" => "Temporarily muting peon ping"}
    ) do |transcript_path|
      assert_equal "Temporarily muting peon ping", SpokenSummary.session_title(transcript_path:)
    end
  end

  def test_nil_without_a_title
    with_transcript({"type" => "user", "message" => {"content" => "hello"}}) do |transcript_path|
      assert_nil SpokenSummary.session_title(transcript_path:)
    end
  end

  def test_nil_when_transcript_is_missing
    assert_nil SpokenSummary.session_title(transcript_path: "/nonexistent/session.jsonl")
  end
end

class AnnouncementTest < Minitest::Test
  def test_session_title_comes_first
    assert_equal "AI Enablement: Code Review. I fixed the test.",
      SpokenSummary.announcement(session_title: "AI Enablement: Code Review", summary: "I fixed the test.")
  end

  def test_summary_alone_without_a_session_title
    assert_equal "I fixed the test.", SpokenSummary.announcement(session_title: nil, summary: "I fixed the test.")
  end
end

class ToggleMuteTest < Minitest::Test
  def test_first_toggle_mutes
    Dir.mktmpdir do |directory|
      mute_file_path = File.join(directory, "spoken-summary", "muted")

      assert_equal :muted, SpokenSummary.toggle_mute(mute_file_path:)
      assert SpokenSummary.muted?(mute_file_path:)
    end
  end

  def test_second_toggle_unmutes
    Dir.mktmpdir do |directory|
      mute_file_path = File.join(directory, "spoken-summary", "muted")
      SpokenSummary.toggle_mute(mute_file_path:)

      assert_equal :unmuted, SpokenSummary.toggle_mute(mute_file_path:)
      refute SpokenSummary.muted?(mute_file_path:)
    end
  end
end

class OneSpeakerAtATimeTest < Minitest::Test
  def test_second_speaker_waits_for_the_first_to_finish
    Dir.mktmpdir do |directory|
      lock_path = File.join(directory, "speaker.lock")
      events = Queue.new
      first_speaking = Queue.new
      first = Thread.new do
        SpokenSummary.one_speaker_at_a_time(lock_path:) do
          events << :first_started
          first_speaking << true
          sleep 0.2
          events << :first_finished
        end
      end
      first_speaking.pop(timeout: 2)
      second = Thread.new do
        SpokenSummary.one_speaker_at_a_time(lock_path:) { events << :second_started }
      end
      [first, second].each(&:join)

      assert_equal %i[first_started first_finished second_started], Array.new(events.size) { events.pop }
    end
  end
end

class PhononRequestBodyTest < Minitest::Test
  def test_asks_phonon_for_hugh_reading_the_summary
    assert_equal({"model" => "phonon", "voice" => "Hugh", "input" => "Merged the PR."},
      JSON.parse(SpokenSummary.phonon_request_body("Merged the PR.")))
  end
end

class SayInputTest < Minitest::Test
  def test_prefixes_the_volume_command
    assert_equal "[[volm 0.5]] Merged the PR.", SpokenSummary.say_input("Merged the PR.")
  end
end

class PromptTest < Minitest::Test
  def test_prompt_wraps_the_message_in_tags
    assert_equal "<message>\nShould I start?\n</message>", SpokenSummary.prompt(message: "Should I start?")
  end

  def test_system_prompt_fixes_who_i_and_you_are
    assert_includes SpokenSummary::SYSTEM_PROMPT, "\"I\" is always the assistant and \"you\" is always the user"
  end

  def test_system_prompt_forbids_answering_the_message
    assert_includes SpokenSummary::SYSTEM_PROMPT, "Never answer or reply to the message"
  end
end
