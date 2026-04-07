# Memcached service setup

class local_dev::memcached {
  homebrew_package { 'memcached':
    ensure => present,
  }

  # Note: both command and unless need HOME for brew to work
  exec { 'start_memcached':
    command     => 'brew services start memcached',
    unless      => 'brew services list | grep memcached | grep started',
    path        => ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin'],
    environment => ["HOME=${::env_home}"],
    require     => Homebrew_package['memcached'],
  }
}
