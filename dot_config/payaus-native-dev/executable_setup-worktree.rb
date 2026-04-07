#!/usr/bin/env ruby
# frozen_string_literal: true

# Set up native local development (puma-dev) for a payaus worktree.
#
# Deploys .pumaenv + Rails initializer + puma-dev symlink so the worktree
# is accessible at https://<name>.test.
#
# Usage:
#   setup-worktree.rb <name>           # set up worktree or main repo
#   setup-worktree.rb --teardown <name> # remove puma-dev symlink
#   setup-worktree.rb --list           # show current puma-dev symlinks
#
# Examples:
#   setup-worktree.rb payaus           # main repo → https://payaus.test
#   setup-worktree.rb slot-1           # worktree  → https://slot-1.test
#   setup-worktree.rb --teardown slot-1

require "fileutils"
require "optparse"

CONFIG_DIR = File.expand_path("..", __FILE__)
MAIN_REPO = File.expand_path("~/programming/payaus")
WORKTREES_DIR = File.expand_path("~/programming/worktrees")
PUMA_DEV_DIR = File.expand_path("~/.puma-dev")

def resolve_path(name)
  if name == "payaus"
    MAIN_REPO
  else
    File.join(WORKTREES_DIR, name)
  end
end

def setup(name)
  worktree_path = resolve_path(name)
  abort "ERROR: #{worktree_path} does not exist" unless Dir.exist?(worktree_path)

  domain = "#{name}.test"

  deploy_pumaenv(worktree_path, name:, domain:)
  verify_pumaenv_safety(worktree_path)
  deploy_initializer(worktree_path)
  create_symlink(name, worktree_path)

  puts ""
  puts "Native dev ready: https://#{domain}"
  puts "  .pumaenv deployed (BOOT_WITHOUT_SECRETS=true verified)"
  puts "  initializer deployed"
  puts "  puma-dev symlink created"
  puts ""
  puts "Next: cd #{worktree_path} && source .pumaenv && yarn watch"
end

def verify_pumaenv_safety(worktree_path)
  pumaenv = File.join(worktree_path, ".pumaenv")
  content = File.read(pumaenv)

  unless content.include?("BOOT_WITHOUT_SECRETS=true")
    abort <<~ERROR
      SAFETY ERROR: .pumaenv is missing BOOT_WITHOUT_SECRETS=true

      Without this, bin/rails commands will load vault credentials and
      target the SHARED REMOTE DEV DATABASE instead of localhost.

      Fix: add 'export BOOT_WITHOUT_SECRETS=true' to #{pumaenv}
      Or: update the env.template in ~/.config/payaus-native-dev/
    ERROR
  end

  unless content.include?("DEV_DATABASE_HOST=localhost")
    abort <<~ERROR
      SAFETY ERROR: .pumaenv has DEV_DATABASE_HOST != localhost

      This would cause Rails to connect to a non-local database.
      Fix: set DEV_DATABASE_HOST=localhost in #{pumaenv}
    ERROR
  end
end

def teardown(name)
  symlink = File.join(PUMA_DEV_DIR, name)
  if File.symlink?(symlink)
    File.delete(symlink)
    puts "Removed puma-dev symlink: #{symlink}"
  else
    puts "No symlink found for #{name}"
  end
end

def list
  puts "puma-dev symlinks:"
  Dir.glob(File.join(PUMA_DEV_DIR, "*")).each do |entry|
    next unless File.symlink?(entry)

    name = File.basename(entry)
    target = File.readlink(entry)
    puts "  #{name}.test → #{target}"
  end
end

def deploy_pumaenv(worktree_path, name:, domain:)
  template = File.join(CONFIG_DIR, "env.template")
  abort "ERROR: env.template not found at #{template}" unless File.exist?(template)

  content = File.read(template)

  # Replace host-specific values
  content.gsub!("APP_HOST_URL=payaus.test", "APP_HOST_URL=#{domain}")
  content.gsub!("VIRTUAL_HOST=payaus.test", "VIRTUAL_HOST=#{domain}")
  content.gsub!("DEFAULT_HOST=payaus.test", "DEFAULT_HOST=#{domain}")
  content.gsub!("QUEUE=payaus.test", "QUEUE=#{domain}")

  dest = File.join(worktree_path, ".pumaenv")
  File.write(dest, content)
end

def deploy_initializer(worktree_path)
  source = File.join(CONFIG_DIR, "initializer.rb")
  abort "ERROR: initializer.rb not found at #{source}" unless File.exist?(source)

  dest = File.join(worktree_path, "config", "initializers", "99_local_native_dev.rb")
  FileUtils.cp(source, dest)
end

def create_symlink(name, worktree_path)
  FileUtils.mkdir_p(PUMA_DEV_DIR)
  symlink = File.join(PUMA_DEV_DIR, name)

  if File.symlink?(symlink)
    existing_target = File.readlink(symlink)
    if existing_target == worktree_path
      puts "Symlink already exists: #{symlink} → #{worktree_path}"
      return
    end

    File.delete(symlink)
  end

  File.symlink(worktree_path, symlink)
end

# Parse arguments
options = {}
OptionParser.new do |o|
  o.banner = "Usage: setup-worktree.rb [options] <name>"
  o.on("--teardown", "Remove puma-dev symlink for worktree") { options[:teardown] = true }
  o.on("--list", "List current puma-dev symlinks") { options[:list] = true }
  o.on("-h", "--help") { puts o; exit }
end.parse!

if options[:list]
  list
elsif options[:teardown]
  name = ARGV[0] || abort("ERROR: provide worktree name")
  teardown(name)
else
  name = ARGV[0] || abort("ERROR: provide worktree name (e.g. 'payaus', 'slot-1')")
  setup(name)
end
