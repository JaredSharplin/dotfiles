# frozen_string_literal: true

# Local native development overrides (puma-dev).
# This file is gitignored and only exists on machines using native local dev.
if ENV["RUNNING_LOCAL_NATIVE_ENV"] == "true"
  Rails.application.configure do
    config.hosts << /.*\.test/
    config.assume_ssl = true
  end

  # Suppress MigrationTimings file mutations on native dev.
  #
  # config/initializers/02_configuration/migration_timings.rb prepends
  # MigrationTimings to ActiveRecord::Migration. On :up in development it
  # captures debug logs and writes them back into the migration .rb file
  # itself (clear_migration_timings strips the existing block, then
  # log_migration_timings appends a fresh one).
  #
  # On a remote dev box with prod-shaped data that's signal worth committing.
  # On native local dev against a tiny seeded DB the timings are meaningless,
  # and every db:migrate / db:reset run rewrites the timing block on every
  # tracked migration that runs locally — producing dozens of timestamp-only
  # diffs that have to be reverted before committing. This override no-ops
  # both methods so migrations run normally but never touch their own files.
  #
  # 99_ prefix ensures this loads after 02_configuration/. The redefinition
  # works because Ruby method lookup hits this MigrationTimings copy before
  # the prepended-into-Migration version.
  if defined?(MigrationTimings)
    module MigrationTimings
      def log_migration_timings; end
      def clear_migration_timings; end
    end
  end
end
