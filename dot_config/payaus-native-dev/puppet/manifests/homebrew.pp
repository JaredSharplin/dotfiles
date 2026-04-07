# Homebrew installation and helper definitions
# This must be included first as other manifests depend on it

class local_dev::homebrew {
  # Ensure Homebrew is available (macOS)
  exec { 'install_homebrew':
    command => '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"',
    creates => '/opt/homebrew/bin/brew',
    path    => ['/usr/bin', '/bin'],
    unless  => 'test -x /opt/homebrew/bin/brew',
  }
}

# Helper for Homebrew packages - defined at top level for use by other classes
# Note: Puppet sanitizes environment for exec, so we must explicitly pass HOME
define homebrew_package (
  $ensure = 'present',
) {
  exec { "brew_install_${name}":
    command     => "/opt/homebrew/bin/brew install ${name}",
    unless      => "/opt/homebrew/bin/brew list ${name}",
    path        => ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin'],
    environment => ["HOME=${::env_home}"],
    require     => Class['local_dev::homebrew'],
  }
}
