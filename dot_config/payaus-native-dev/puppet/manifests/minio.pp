# MinIO S3-compatible object storage for local development
# Provides S3-compatible API matching production environment
# Uses Homebrew services for service management

class local_dev::minio (
  String $bucket_name = 'payaus-development',
) {
  # Homebrew's default minio data directory
  $data_dir = '/opt/homebrew/var/minio'

  homebrew_package { 'minio':
    ensure => present,
  }

  homebrew_package { 'minio-mc':
    ensure => present,
  }

  # Create the default bucket directory in Homebrew's data location
  file { $data_dir:
    ensure  => directory,
    mode    => '0755',
    require => Homebrew_package['minio'],
  }

  file { "${data_dir}/${bucket_name}":
    ensure  => directory,
    mode    => '0755',
    require => File[$data_dir],
  }

  # Start MinIO using Homebrew services
  exec { 'start_minio':
    command     => '/opt/homebrew/bin/brew services start minio',
    unless      => '/opt/homebrew/bin/brew services list | grep minio | grep -q started',
    path        => ['/opt/homebrew/bin', '/usr/bin', '/bin'],
    environment => ["HOME=${::env_home}"],
    require     => [Homebrew_package['minio'], File[$data_dir]],
  }

  # Configure mc (MinIO client) alias after service starts
  exec { 'configure_minio_alias':
    command     => '/opt/homebrew/bin/mc alias set local http://localhost:9000 minioadmin minioadmin',
    unless      => '/opt/homebrew/bin/mc alias list | grep -q "^local"',
    path        => ['/opt/homebrew/bin', '/usr/bin', '/bin'],
    environment => ["HOME=${::env_home}"],
    require     => [Homebrew_package['minio-mc'], Exec['start_minio']],
  }
}
