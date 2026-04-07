#!/bin/bash
# Ensure native local development services are running.
# Usage: ~/.config/payaus-native-dev/ensure-services.sh [project-root]
#
# If project-root is not provided, defaults to ~/programming/payaus.
# Uses Puppet to declaratively manage: PostgreSQL, Memcached, MinIO, puma-dev.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/puppet/manifests"
PROJECT_ROOT="${1:-$HOME/programming/payaus}"

if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "ERROR: Project root does not exist: $PROJECT_ROOT"
    exit 1
fi

RUBY_VERSION_FILE="${PROJECT_ROOT}/.ruby-version"
if [[ -f "$RUBY_VERSION_FILE" ]]; then
    RUBY_VERSION="$(cat "$RUBY_VERSION_FILE" | tr -d '[:space:]')"
else
    RUBY_VERSION="3.4.2"
fi

APP_NAME="$(basename "$PROJECT_ROOT")"

echo "=========================================="
echo "Local Development Environment Setup"
echo "=========================================="
echo ""
echo "Project: ${APP_NAME}"
echo "Root:    ${PROJECT_ROOT}"
echo "Ruby:    ${RUBY_VERSION}"
echo ""

# Add Puppet to PATH if installed at known location
if ! command -v puppet &> /dev/null && [[ -x /opt/puppetlabs/bin/puppet ]]; then
    export PATH="/opt/puppetlabs/bin:$PATH"
fi

if ! command -v puppet &> /dev/null; then
    echo "ERROR: Puppet is not installed."
    echo "  brew install --cask puppetlabs/puppet/puppet-agent-8"
    exit 1
fi

echo "Puppet version: $(puppet --version)"
echo ""

echo "Applying local development manifest..."
echo ""

COMBINED_MANIFEST=$(mktemp)
trap "rm -f $COMBINED_MANIFEST" EXIT

cat "${MANIFEST_DIR}/homebrew.pp" \
    "${MANIFEST_DIR}/postgresql.pp" \
    "${MANIFEST_DIR}/memcached.pp" \
    "${MANIFEST_DIR}/minio.pp" \
    "${MANIFEST_DIR}/ruby.pp" \
    "${MANIFEST_DIR}/puma_dev.pp" \
    "${MANIFEST_DIR}/local_dev_setup.pp" \
    > "$COMBINED_MANIFEST"

set +e
FACTER_project_root="$PROJECT_ROOT" \
FACTER_ruby_version="$RUBY_VERSION" \
FACTER_app_name="$APP_NAME" \
FACTER_env_home="$HOME" \
FACTER_env_user="$USER" \
puppet apply "$COMBINED_MANIFEST" --verbose --detailed-exitcodes
PUPPET_EXIT_CODE=$?
set -e

case $PUPPET_EXIT_CODE in
  0|2)
    if command -v puma-dev &> /dev/null; then
      if ! launchctl list 2>/dev/null | grep -q io.puma.dev; then
        echo ""
        echo "ACTION REQUIRED: puma-dev LaunchAgent not installed."
        echo "  sudo puma-dev -setup"
        echo "  puma-dev -install"
        exit 1
      fi
    else
      echo ""
      echo "ERROR: puma-dev not found."
      echo "  brew tap puma/puma && brew install puma-dev"
      echo "  sudo puma-dev -setup"
      echo "  puma-dev -install"
      exit 1
    fi

    echo ""
    echo "Services running: PostgreSQL, Memcached, MinIO, puma-dev"
    echo "Ready for native local development."
    ;;
  *)
    echo ""
    echo "ERROR: Puppet encountered failures (exit code: $PUPPET_EXIT_CODE)"
    exit 1
    ;;
esac
