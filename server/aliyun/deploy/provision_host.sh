#!/usr/bin/env bash
# Run on the ECS host as root after reviewing this file. Never touches DB storage.
set -euo pipefail
umask 027

validate_service_account() {
  local service_group_id account_user_id account_primary_group_id member_group_id
  service_group_id=$(getent group goufayu | cut -d: -f3)
  account_user_id=$(id -u goufayu)
  account_primary_group_id=$(id -g goufayu)
  [[ $service_group_id =~ ^[0-9]+$ && $service_group_id -gt 0 &&
     $account_user_id =~ ^[0-9]+$ && $account_user_id -gt 0 &&
     $account_primary_group_id == "$service_group_id" ]] || {
    echo 'Existing goufayu account must be non-root with its dedicated non-root primary group.' >&2
    return 1
  }
  for member_group_id in $(id -G goufayu); do
    [[ $member_group_id == "$service_group_id" ]] || {
      echo 'Existing goufayu account has extra group membership; review it before provisioning.' >&2
      return 1
    }
  done
}

[[ ${EUID} -eq 0 ]] || { echo 'root is required for host provisioning' >&2; exit 1; }
[[ ${1:-} == --install-os-packages ]] || {
  echo 'Usage: provision_host.sh --install-os-packages' >&2; exit 2;
}
command -v dnf >/dev/null
command -v podman >/dev/null
systemctl is-active --quiet goufayu-db.service || {
  echo 'Existing goufayu-db.service must already be running; it will not be recreated.' >&2; exit 1;
}
# Use the configured Alibaba Linux repositories. Do not change /usr/bin/python.
dnf install -y python3.11 python3.11-pip lua logrotate iproute
python3.11 -c 'import sys; assert sys.version_info[:2] == (3, 11)'
getent group goufayu >/dev/null || groupadd --system goufayu
service_group_id=$(getent group goufayu | cut -d: -f3)
[[ $service_group_id =~ ^[0-9]+$ && $service_group_id -gt 0 ]] || {
  echo 'Refusing a root or invalid goufayu group.' >&2; exit 1;
}
id goufayu >/dev/null 2>&1 || useradd --system --gid goufayu --home-dir /var/lib/goufayu --shell /sbin/nologin goufayu
validate_service_account
for managed_directory in /opt/goufayu /opt/goufayu/releases /etc/goufayu /var/log/goufayu /var/lib/goufayu /var/backups/goufayu; do
  [[ ! -L $managed_directory ]] || { echo 'Refusing symlink in managed deployment directories.' >&2; exit 1; }
done
install -d -o root -g root -m 0755 /opt/goufayu /opt/goufayu/releases
install -d -o root -g goufayu -m 0750 /etc/goufayu /var/log/goufayu
install -d -o root -g root -m 0700 /var/lib/goufayu /var/backups/goufayu
[[ ! -L /var/log/goufayu/api.log && ( ! -e /var/log/goufayu/api.log || -f /var/log/goufayu/api.log ) ]] || {
  echo 'Refusing symlink or non-file at API log path' >&2; exit 1;
}
touch /var/log/goufayu/api.log
chown root:goufayu /var/log/goufayu/api.log
chmod 0660 /var/log/goufayu/api.log
printf '%s\n' 'Host directories and Python 3.11 are ready. DB storage/container unchanged.'
