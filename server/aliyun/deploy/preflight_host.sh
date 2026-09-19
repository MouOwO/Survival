#!/usr/bin/env bash
# Read-only ECS inventory. No install, service restart, role change or file write.
set +x
set -euo pipefail
[[ ${EUID} -eq 0 ]] || { echo 'PREFLIGHT_ERROR root_required' >&2; exit 1; }
[[ $# -eq 0 || ( $# -eq 2 && $1 == --db-admin-user ) ]] || {
  echo 'Usage: preflight_host.sh [--db-admin-user postgres]' >&2; exit 2;
}
admin_user=${2:-postgres}
[[ $admin_user =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || exit 2

printf '%s\n' '[host]'
cat /etc/os-release
uname -m
rpm -q systemd python3.11 python3.11-pip lua logrotate iproute || true
df -h / /data /opt
free -m
printf '%s\n' '[existing services; no environment values]'
for unit in goufayu-db.service goufayu-api.service goufayu-backup.timer; do
  systemctl show "$unit" --property=Id,LoadState,ActiveState,SubState,UnitFileState,User,Group,MainPID,Restart
done
printf '%s\n' '[database container; no container environment values]'
systemctl is-active --quiet goufayu-db.service
podman container exists goufayu-db
podman inspect --format '{{.State.Status}}' goufayu-db
podman inspect --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}' goufayu-db
podman port goufayu-db
printf '%s\n' '[listening ports]'
ss -lnt '( sport = :22 or sport = :5432 or sport = :8765 or sport = :80 or sport = :443 )'
printf '%s\n' '[deployment paths and accounts; metadata only]'
getent passwd goufayu || true
getent group goufayu || true
for item in /opt/goufayu /opt/goufayu/releases/current /etc/goufayu /var/log/goufayu \
    /etc/goufayu/postgres-password /etc/goufayu/api-token /etc/goufayu/account-pepper /etc/goufayu/api.env; do
  if [[ -e $item || -L $item ]]; then
    stat -c '%a %U:%G %F %n' "$item"
    [[ ! -L $item ]] || readlink "$item"
  else
    printf 'ABSENT %s\n' "$item"
  fi
done

# Reuse the existing administrator credential without printing it or including
# it in argv. Podman takes the environment VARIABLE NAME, never its value.
secret=/etc/goufayu/postgres-password
[[ -f $secret && ! -L $secret ]] || { echo 'PREFLIGHT_ERROR existing_admin_secret_required' >&2; exit 1; }
secret_owner=$(stat -c '%u' "$secret")
secret_mode=$(stat -c '%a' "$secret")
[[ $secret_owner == 0 && ( $secret_mode == 600 || $secret_mode == 400 ) ]] || {
  echo 'PREFLIGHT_ERROR admin_secret_requires_root_private_permissions' >&2; exit 1;
}
PGPASSWORD=$(<"$secret")
export PGPASSWORD
trap 'unset PGPASSWORD PGOPTIONS' EXIT
export PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=10000 -c lock_timeout=2000'
printf '%s\n' '[database identity, roles, schemas and exact counts; no player values]'
podman exec -i --env PGPASSWORD --env PGOPTIONS goufayu-db \
  psql -X --no-password --host=127.0.0.1 --port=5432 --username="$admin_user" \
    --dbname=goufayu_test --set=ON_ERROR_STOP=1 --pset=pager=off <<'SQL'
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL row_security=off;
SELECT current_database() AS database, current_user AS administrator,
       current_setting('server_version') AS version;
SELECT pg_get_userbyid(datdba) AS database_owner FROM pg_database WHERE datname=current_database();
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls
FROM pg_roles WHERE rolname IN ('goufayu_owner','goufayu_migrator','goufayu_app');
SELECT extname, extversion FROM pg_extension ORDER BY extname;
SELECT nspname FROM pg_namespace
WHERE nspname <> 'information_schema' AND nspname !~ '^pg_' ORDER BY 1;
SELECT schemaname, tablename, tableowner FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1,2;
SELECT format('SELECT %L AS relation, count(*) AS exact_rows FROM %I.%I;',
              schemaname || '.' || tablename, schemaname, tablename)
FROM pg_tables WHERE schemaname IN ('public','extensions') ORDER BY 1
\gexec
SELECT n.nspname AS schema, p.proname AS routine, p.prosecdef AS security_definer,
       pg_get_userbyid(p.proowner) AS owner
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('public','extensions') ORDER BY 1,2;
COMMIT;
SQL
unset PGPASSWORD PGOPTIONS
printf '%s\n' 'READ_ONLY_PREFLIGHT_COMPLETE; inspect results before choosing empty install or backup/migration.'
