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

  # Run `yarn install --frozen-lockfile` only when yarn.lock is newer than
  # the stamp from our last install (or the stamp is missing). Lets watch
  # and build skip the ~10s install when nothing has changed.
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
      system("yarn", "install", "--frozen-lockfile", exception: true)
    end
    FileUtils.mkdir_p(File.dirname(stamp))
    FileUtils.touch(stamp)
    :installed
  end
end
