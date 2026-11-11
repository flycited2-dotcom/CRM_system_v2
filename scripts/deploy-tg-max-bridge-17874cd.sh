#!/usr/bin/env bash
set -euo pipefail
umask 077

old_head=99b598cc8effff4efb400084f80e5cf102480903
expected_head=3363b7aed8c99541f177ebb9b91bc9edab3388ae
app_dir=/opt/tg-max-bridge
backup_dir=/root/migration-backups/tg-max/20260719-before-17874cd
unit=/etc/systemd/system/tg-max-bridge.service

rollback() {
  local original_code=$?
  trap - ERR
  set +e
  systemctl stop tg-max-bridge.service
  git -C "$app_dir" checkout --detach "$old_head"
  install -m 0644 "$backup_dir/tg-max-bridge.service" "$unit"
  systemctl daemon-reload
  systemctl start tg-max-bridge.service
  exit "$original_code"
}

test "$(git -C "$app_dir" rev-parse HEAD)" = "$old_head"
initial_status=$(git -C "$app_dir" status --porcelain)
test -z "$initial_status" || test "$initial_status" = '?? bridge.log.1'
test "$(systemctl is-active tg-max-bridge.service)" = active
test -f "$app_dir/.env"
test -f "$app_dir/max_session.json"
test -f "$app_dir/bridge.log"

git -C "$app_dir" fetch origin main
test "$(git -C "$app_dir" rev-parse FETCH_HEAD)" = "$expected_head"

install -d -m 0700 "$backup_dir"
if [[ ! -f "$backup_dir/tg-max-bridge.service" ]]; then
  install -m 0644 "$unit" "$backup_dir/tg-max-bridge.service"
fi

trap rollback ERR
systemctl stop tg-max-bridge.service
test "$(systemctl is-active tg-max-bridge.service || true)" = inactive

if [[ ! -f "$backup_dir/tg-max-runtime-before-17874cd.tar.gz" ]]; then
  tar -C "$app_dir" -czf "$backup_dir/tg-max-runtime-before-17874cd.tar.gz" \
    .env max_session.json bridge.log debug
fi
tar -tzf "$backup_dir/tg-max-runtime-before-17874cd.tar.gz" >/dev/null
chmod 0600 "$backup_dir/tg-max-runtime-before-17874cd.tar.gz"

git -C "$app_dir" checkout main
git -C "$app_dir" merge --ff-only "$expected_head"
test "$(git -C "$app_dir" rev-parse HEAD)" = "$expected_head"
test -z "$(git -C "$app_dir" status --porcelain)"

cd "$app_dir"
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python -m py_compile bot.py logging_config.py tests/test_logging_config.py

chmod 0600 .env max_session.json bridge.log
find . -maxdepth 1 -type f -name 'bridge.log.*' -exec chmod 0600 {} +
find debug -type d -exec chmod 0700 {} +
find debug -type f -exec chmod 0600 {} +
install -m 0644 tg-max-bridge.service "$unit"
systemctl daemon-reload
systemd-analyze verify tg-max-bridge.service
systemctl reset-failed tg-max-bridge.service

start_time=$(date --iso-8601=seconds)
systemctl enable tg-max-bridge.service >/dev/null
systemctl start tg-max-bridge.service
sleep 12

test "$(systemctl is-active tg-max-bridge.service)" = active
test "$(systemctl is-enabled tg-max-bridge.service)" = enabled
test "$(systemctl show tg-max-bridge.service -p NRestarts --value)" = 0
test "$(systemctl show tg-max-bridge.service -p ExecMainStatus --value)" = 0
test -z "$(git status --porcelain)"
test "$(stat -c %a .env)" = 600
test "$(stat -c %a max_session.json)" = 600
test "$(stat -c %a bridge.log)" = 600

logs=$(journalctl -u tg-max-bridge.service --since "$start_time" --no-pager -o cat)
test "$(printf '%s\n' "$logs" | grep -c 'Application started')" -ge 1
test "$(printf '%s\n' "$logs" | grep -Eic \
  'traceback|conflict.*getupdates|(^|[^a-z])error([^a-z]|$)' || true)" = 0
test "$(printf '%s\n' "$logs" | grep -c 'HTTP Request:' || true)" = 0

token=$(.venv/bin/python -c \
  'from dotenv import dotenv_values; print(dotenv_values(".env")["BOT_TOKEN"])')
test -n "$token"
if printf '%s\n' "$logs" | grep -Fq "$token"; then
  exit 1
fi

printf 'release_head=%s\n' "$expected_head"
printf 'service_active=active\n'
printf 'service_restarts=0\n'
printf 'post_start_error_lines=0\n'
printf 'post_start_http_request_lines=0\n'
printf 'secret_in_post_start_logs=no\n'
printf 'bridge_log_mode=%s\n' "$(stat -c %a bridge.log)"
printf 'session_mode=%s\n' "$(stat -c %a max_session.json)"
printf 'debug_files=%s\n' "$(find debug -type f | wc -l)"
printf 'runtime_backup_sha256='
sha256sum "$backup_dir/tg-max-runtime-before-17874cd.tar.gz" | awk '{print $1}'

trap - ERR
