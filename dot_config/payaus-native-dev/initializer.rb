# frozen_string_literal: true

# Local native development overrides (puma-dev).
# This file is gitignored and only exists on machines using native local dev.
if ENV["RUNNING_LOCAL_NATIVE_ENV"] == "true"
  Rails.application.configure do
    config.hosts << /.*\.test/
    config.assume_ssl = true
  end
end
