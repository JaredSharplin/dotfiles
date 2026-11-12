#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

# Stop hook: asks Haiku for a one-sentence spoken summary of Claude's last
# message and reads it aloud with macOS `say`.
module SpokenSummary
  VOICE = "Lee (Premium)"
  VOLUME = 0.6
  MESSAGE_CHARACTER_LIMIT = 4000
  CHILD_SESSION_VARIABLE = "SPOKEN_SUMMARY_CHILD"
  PULL_REQUEST_NUMBER = /\b(?:the\s+)?(?:PR|pull request)\s*#?\d+/i
  ISSUE_NUMBER = /\s*#\d+\b/
  COMMIT_HASH_WITH_PREPOSITION = /\s*(?:\b(?:as|in|at)\s+)?\b(?=\h*\d)(?=\h*[a-f])\h{7,40}\b/i

  def self.message_to_summarise(hook_input:, environment:)
    return if environment.key?(CHILD_SESSION_VARIABLE)
    return if hook_input["stop_hook_active"]

    message = hook_input["last_assistant_message"].to_s.strip
    message[0, MESSAGE_CHARACTER_LIMIT] unless message.empty?
  end

  def self.prompt(message:)
    <<~PROMPT.chomp
      Below is the final message an AI coding assistant just sent its user.
      Summarise it in one short sentence that will be spoken aloud.
      Plain text only: no markdown, code, file paths, commit hashes or quotes.
      Never say a pull request or issue number; describe what it is about instead.
      Example: "Committed as 7bfe64d and opened PR #56255" becomes
      "Committed it and opened the PR that adds spoken summaries."
      Reply with the sentence and nothing else.

      #{message}
    PROMPT
  end

  def self.summarise(message:)
    summary, status = Open3.capture2(
      {CHILD_SESSION_VARIABLE => "1"},
      "claude", "-p", "--model", "haiku", "--no-session-persistence",
      "--strict-mcp-config", "--setting-sources", "", "--disable-slash-commands", "--tools", "",
      stdin_data: prompt(message:)
    )
    summary.strip if status.success?
  end

  def self.speakable(summary)
    summary
      .gsub(PULL_REQUEST_NUMBER, "the PR")
      .gsub(ISSUE_NUMBER, "")
      .gsub(COMMIT_HASH_WITH_PREPOSITION, "")
      .squeeze(" ")
      .strip
  end

  def self.speech_input(summary) = "[[volm #{VOLUME}]] #{summary}"

  def self.call(hook_input:, environment:)
    message = message_to_summarise(hook_input:, environment:) or return
    summary = summarise(message:)&.then { speakable(it) }
    Open3.capture2("say", "-v", VOICE, "-f", "-", stdin_data: speech_input(summary)) unless summary.to_s.empty?
  end
end

if $PROGRAM_NAME == __FILE__
  hook_input = begin
    JSON.parse($stdin.read)
  rescue JSON::ParserError
    exit 0
  end
  SpokenSummary.call(hook_input:, environment: ENV.to_h)
end
