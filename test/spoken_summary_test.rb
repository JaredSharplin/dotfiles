#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"

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

  def test_keeps_plain_numbers
    assert_equal "Fixed 3 tests across 1234567 rows.",
      SpokenSummary.speakable("Fixed 3 tests across 1234567 rows.")
  end

  def test_replaces_pull_request_number_with_the_pr
    assert_equal "Opened the PR which adds spoken summaries.",
      SpokenSummary.speakable("Opened PR #56255 which adds spoken summaries.")
  end

  def test_replaces_spelled_out_pull_request_number
    assert_equal "Updated the PR.",
      SpokenSummary.speakable("Updated pull request 123.")
  end

  def test_does_not_double_the_article
    assert_equal "Merged the PR.",
      SpokenSummary.speakable("Merged the PR #42.")
  end

  def test_removes_bare_issue_number
    assert_equal "Closed it.",
      SpokenSummary.speakable("Closed it #42.")
  end
end

class SpeechInputTest < Minitest::Test
  def test_prefixes_the_volume_command
    assert_equal "[[volm 0.6]] Merged the PR.", SpokenSummary.speech_input("Merged the PR.")
  end
end

class PromptTest < Minitest::Test
  def test_prompt_ends_with_the_message
    prompt = SpokenSummary.prompt(message: "Fixed the test.")

    assert prompt.end_with?("\n\nFixed the test.")
  end
end
