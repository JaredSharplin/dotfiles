# frozen_string_literal: true

# Shared helpers for payaus-native-dev wrapper scripts.
# Deployed alongside the executables at ~/.config/payaus-native-dev/.

require "fileutils"
require "pathname"

module PayausNativeDev
  module_function

  def require_pumaenv!
    pumaenv = find_pumaenv
    abort <<~ERR unless pumaenv
      ERROR: No .pumaenv found in current directory or parents.
      Run: ~/.config/payaus-native-dev/setup-worktree.rb <name>
    ERR

    load_pumaenv(pumaenv)
    # Echo the resolved root to stderr (never stdout — watch's stdout is
    # webpack's compile stream). cwd-ascent can silently land on the wrong
    # checkout when the shell's cwd has drifted; surfacing the target makes
    # that visible in the first line instead of after a debugging session.
    warn "native-dev: resolved project root → #{File.dirname(pumaenv)}"
    pumaenv
  end

  def find_pumaenv
    Pathname.pwd.ascend do |path|
      candidate = path.join(".pumaenv")
      return candidate if candidate.exist?
    end
    nil
  end

  def load_pumaenv(path)
    File.readlines(path).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      line = line.delete_prefix("export ")
      key, value = line.split("=", 2)
      next unless key && value

      value = value.delete_prefix('"').delete_suffix('"')
      value = value.delete_prefix("'").delete_suffix("'")
      ENV[key] = value
    end
  end

  # Ensure the repo's pinned toolchain (node + yarn, per mise.toml) is
  # trusted and installed, so subsequent `mise exec` calls resolve to the
  # versions the repo declares. Cheap no-op once everything is present.
  #
  # This is why we don't rely on a bare `yarn` on PATH: the shell uses
  # `mise activate` (not shims), which computes PATH at directory-change
  # time. A yarn version that didn't exist when the shell cd'd in won't be
  # on PATH after we install it mid-run — so callers must invoke tools via
  # `mise exec`, which re-resolves against the freshly-installed versions.
  def ensure_toolchain!(project_root)
    Dir.chdir(project_root) do
      system("mise", "trust", exception: true)
      system("mise", "install", exception: true)
    end
  end

  # Ensure the bundle satisfies the current Gemfile.lock, healing the most
  # common native-dev breakage: a `git town sync` merges master and advances
  # the git-sourced gem revisions (rails itself is a git gem here), but the
  # worktree's bundle is never reinstalled. Every Rails boot then dies on a
  # Bundler::PathError — including the `./bin/rails runner` that
  # rails-erb-loader spawns to render routes.js.erb, which webpack surfaces
  # only as the opaque "rails-erb-loader failed with code: 1". `bundle check`
  # is a ~1s no-op when the bundle is satisfied, so running it on every boot
  # is cheap and self-heals the drift the way ensure_toolchain! does for the
  # node/yarn pins. Invoked via `mise exec` for the same reason yarn is — to
  # resolve ruby/bundler against the repo's pinned toolchain.
  def ensure_bundle!(project_root)
    Dir.chdir(project_root) do
      return :current if system("mise", "exec", "--", "bundle", "check",
                                 out: File::NULL, err: File::NULL)

      warn "native-dev: bundle out of date (a sync likely advanced a gem " \
           "revision) — running bundle install"
      system("mise", "exec", "--", "bundle", "install", exception: true)
      :installed
    end
  end

  # Run `yarn install` only when yarn.lock is newer than the stamp from our
  # last install (or the stamp is missing). Lets watch and build skip the
  # ~10s install when nothing has changed.
  #
  # Pass skip: true to bypass entirely (e.g. --skip-install flag).
  def ensure_yarn_install!(project_root, skip: false)
    return :skipped if skip

    lockfile = File.join(project_root, "yarn.lock")
    stamp = File.join(project_root, "node_modules", ".native-dev-install-stamp")

    needed = !File.exist?(stamp) ||
      (File.exist?(lockfile) && File.mtime(lockfile) > File.mtime(stamp))

    return :current unless needed

    Dir.chdir(project_root) do
      # Yarn 4: --immutable replaces the removed --frozen-lockfile.
      # `mise exec` resolves yarn to the repo's pinned version (see
      # ensure_toolchain! for why a bare `yarn` isn't reliable here).
      system("mise", "exec", "--", "yarn", "install", "--immutable", exception: true)
    end
    FileUtils.mkdir_p(File.dirname(stamp))
    FileUtils.touch(stamp)
    :installed
  end
end
