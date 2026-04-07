# Ruby version check
# Supports rbenv, mise, and rvm

class local_dev::ruby (
  String $version = '3.4.2',
) {
  exec { 'check_ruby_version':
    command => "/bin/bash -c '
      echo \"\"
      echo \"=================================================================================\"
      echo \"ERROR: Ruby ${version} not found!\"
      echo \"=================================================================================\"
      echo \"\"
      echo \"Please install Ruby ${version} using your preferred version manager:\"
      echo \"\"
      echo \"  rbenv:  rbenv install ${version} && rbenv global ${version}\"
      echo \"  mise:   mise install ruby@${version} && mise use -g ruby@${version}\"
      echo \"  rvm:    rvm install ${version} && rvm use ${version} --default\"
      echo \"\"
      echo \"Then re-run this script.\"
      echo \"=================================================================================\"
      exit 1
    '",
    unless  => "/bin/bash -c '
      # Check rbenv
      if command -v rbenv &>/dev/null; then
        rbenv versions 2>/dev/null | grep -q \"${version}\" && exit 0
      fi
      # Check mise
      if command -v mise &>/dev/null; then
        mise list ruby 2>/dev/null | grep -q \"${version}\" && exit 0
      fi
      # Check rvm
      if command -v rvm &>/dev/null; then
        rvm list 2>/dev/null | grep -q \"${version}\" && exit 0
      fi
      # Check if system ruby matches
      ruby -v 2>/dev/null | grep -q \"${version}\" && exit 0
      exit 1
    '",
    path    => ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin', "${::env_home}/.rbenv/bin", "${::env_home}/.rvm/bin"],
  }
}
