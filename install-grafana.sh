#!/bin/bash

source /etc/os-release
if [ "${ID}" = "rhel" ] || [[ "${ID_LIKE}" =~ .*"rhel".* ]]; then
  echo "Installing Grafana OSS repo and latest stable version"
  cat > /etc/yum.repos.d/grafana-oss.repo <<ENDF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
ENDF
  yum -y install grafana 
  echo "Complete"
elif [ "${ID}" = "sles" ]; then
  version=$(wget -qO- 'https://api.github.com/repos/grafana/grafana/releases/latest' | grep tag_name | sed -e 's/^.*tag_name\":.*\"v\(.*\)".*/\1/')
  wget https://dl.grafana.com/oss/release/grafana-${version}-1.x86_64.rpm
  sudo rpm -i --nodeps grafana-${version}-1.x86_64.rpm
  echo "Installed version $version of Grafana OSS"
elif [ "${ID}" = "ubuntu" ]; then
  echo "Installing Grafana OSS repo and latest stable version"
  apt update
  apt install -y apt-transport-https
  apt install -y software-properties-common wget
  wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
  echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
  apt update
  apt install -y grafana 
  echo "Complete"
else
  echo "Unknown distribution"
  exit 1
fi

if [ "$1" = "-d" ]; then
  # enable debug by default
  perl -pi -e s'#;level = info#level = debug#g' /etc/grafana/grafana.ini 
fi

disable_ssl_auth_client=0
if [ -e "/etc/cm-release" ]; then
  # As of Bright Computing version 9.x, firewall can be controlled by cmdaemon
  versioninfo=$(cat "/etc/cm-release")
  if [[ "$versioninfo" =~ v([0-9]+)\.([0-9]+) ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    if [ "$major" = "9" ]; then
      if [ "$minor" = "0" ]; then
        role="login"
        disable_ssl_auth_client=1
      elif [ "$minor" = "1" ]; then
        role="firewall"
        disable_ssl_auth_client=1
      else
        role="firewall"
      fi
    fi
  elif [[ "$versioninfo" =~ 'vmaster' || "$versioninfo" =~ 'vtrunk' || "$versioninfo" =~ 'v1trunk' ]]; then
    role="firewall"
  fi

  port=3000
  if [ ! -z "$role" ]; then
    echo "Opening port $port in the headnode firewall for Grafana access"
    cat<<EOF | cmsh
device foreach -t headnode -l firewall -i ( \
roles; \
use firewall; \
openports; \
add ACCEPT net $port tcp; \
set description grafana; \
commit)
EOF
  else
    echo "Make sure to open the local firewall to port $port"
  fi

  if [ $disable_ssl_auth_client -gt 0 ]; then
    echo "Disable SSL client CA in the cmdaemon HTTP server"
    base_dir=$(dirname "$0")
    $base_dir/cm-manipulate-advanced-config.py -q "AddSSLClientCA=0"
    if [ $? -gt 0 ]; then
      service cmd restart
    fi
  fi
fi
