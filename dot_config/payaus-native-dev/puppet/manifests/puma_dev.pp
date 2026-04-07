# puma-dev setup for local Rails development
# Listens on ports 80/443 by default (launchd handles privileged port binding).
# puma-dev -install must be run separately as it may prompt for keychain access.

class local_dev::puma_dev (
  String $project_root,
  String $app_name = 'payaus',
) {
  homebrew_package { 'puma-dev':
    ensure => present,
  }

  # Ensure ~/.puma-dev directory exists
  file { "${::env_home}/.puma-dev":
    ensure => directory,
    mode   => '0755',
  }

  # Create symlink for the app in puma-dev
  file { "${::env_home}/.puma-dev/${app_name}":
    ensure  => link,
    target  => $project_root,
    require => File["${::env_home}/.puma-dev"],
  }
}
