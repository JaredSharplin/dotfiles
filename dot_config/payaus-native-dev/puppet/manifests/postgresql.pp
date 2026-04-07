# PostgreSQL check - supports Postgres.app or Homebrew postgresql

class local_dev::postgresql {
  $psql_path = ['/Applications/Postgres.app/Contents/Versions/latest/bin', '/opt/homebrew/opt/postgresql@17/bin', '/opt/homebrew/opt/postgresql@16/bin', '/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin']
  $psql_path_str = '/Applications/Postgres.app/Contents/Versions/latest/bin:/opt/homebrew/opt/postgresql@17/bin:/opt/homebrew/opt/postgresql@16/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin'
  $dev_user = 'payaus_local'

  exec { 'check_postgresql':
    command => "/bin/bash -c '
      echo \"\"
      echo \"=================================================================================\"
      echo \"ERROR: PostgreSQL not found or not running!\"
      echo \"=================================================================================\"
      echo \"\"
      echo \"Install PostgreSQL via Postgres.app or Homebrew:\"
      echo \"  Postgres.app: https://postgresapp.com\"
      echo \"  Homebrew:     brew install postgresql@17\"
      echo \"\"
      echo \"Ensure it is running, then re-run this script.\"
      echo \"=================================================================================\"
      exit 1
    '",
    unless  => "/bin/bash -c '
      export PATH=\"${psql_path_str}\"
      command -v psql &>/dev/null || exit 1
      psql -U postgres -c \"SELECT 1\" &>/dev/null && exit 0
      psql -d postgres -c \"SELECT 1\" &>/dev/null && exit 0
      exit 0
    '",
    path    => $psql_path,
  }

  exec { 'create_dev_user':
    command => "/bin/bash -c '
      export PATH=\"${psql_path_str}\"
      echo \"Creating PostgreSQL user: ${dev_user}\"
      psql -d postgres -c \"CREATE USER ${dev_user} WITH SUPERUSER CREATEDB PASSWORD '\\''password'\\''\"
      echo \"User ${dev_user} created successfully\"
    '",
    unless  => "/bin/bash -c '
      export PATH=\"${psql_path_str}\"
      psql -d postgres -tAc \"SELECT 1 FROM pg_roles WHERE rolname='\''${dev_user}'\''\" | grep -q 1
    '",
    require => Exec['check_postgresql'],
    path    => $psql_path,
  }
}
