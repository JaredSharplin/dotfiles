# Puppet manifest for local development environment setup
# Run with: bin/start_local_native.sh
#
# This sets up services required for running the Rails app outside of Docker containers.
# Based on the compose.yml services: PostgreSQL, Memcached, and supporting tools.

# =============================================================================
# Configuration
# =============================================================================

# Facts passed by apply.sh (use $:: prefix to access):
#   - $::ruby_version: from .ruby-version file
#   - $::project_root: repository root directory
#   - $::app_name: directory name of project root

# =============================================================================
# Include all components in order
# =============================================================================

# Homebrew must come first
include local_dev::homebrew

# Core services
include local_dev::postgresql
include local_dev::memcached

# MinIO S3-compatible storage (uses brew services, ports 9000/9001)
class { 'local_dev::minio':
  bucket_name => "${::app_name}-development",
}

# Ruby version check
class { 'local_dev::ruby':
  version => $::ruby_version,
}

# puma-dev for Rails
class { 'local_dev::puma_dev':
  project_root => $::project_root,
  app_name     => $::app_name,
}

# Summary notification is printed by ensure_running.sh for proper formatting
