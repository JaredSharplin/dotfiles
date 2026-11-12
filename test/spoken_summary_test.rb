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

class PromptTest < Minitest::Test
  def test_prompt_ends_with_the_message
    prompt = SpokenSummary.prompt(message: "Fixed the test.")

    assert prompt.end_with?("\n\nFixed the test.")
  end
end
