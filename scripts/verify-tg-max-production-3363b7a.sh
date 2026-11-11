#!/usr/bin/env bash
set -euo pipefail

app_dir=/opt/tg-max-bridge
expected_head=3363b7aed8c99541f177ebb9b91bc9edab3388ae
backup=/root/migration-backups/tg-max/20260719-before-17874cd/tg-max-runtime-before-17874cd.tar.gz

test "$(git -C "$app_dir" rev-parse HEAD)" = "$expected_head"
test -z "$(git -C "$app_dir" status --porcelain)"
test "$(systemctl is-active tg-max-bridge.service)" = active
test "$(systemctl is-enabled tg-max-bridge.service)" = enabled
test "$(systemctl show tg-max-bridge.service -p NRestarts --value)" = 0
test "$(systemctl show tg-max-bridge.service -p ExecMainStatus --value)" = 0
cmp -s "$app_dir/tg-max-bridge.service" \
  /etc/systemd/system/tg-max-bridge.service

test "$(stat -c %a "$app_dir/.env")" = 600
test "$(stat -c %a "$app_dir/max_session.json")" = 600
test "$(stat -c %a "$app_dir/bridge.log")" = 600
test "$(find "$app_dir/debug" -type f ! -perm 0600 | wc -l)" = 0
test "$(find "$app_dir/debug" -type d ! -perm 0700 | wc -l)" = 0
test -s "$backup"
tar -tzf "$backup" >/dev/null

current_log_size=$(stat -c %s "$app_dir/bridge.log")
test "$current_log_size" -le $((10 * 1024 * 1024))

started=$(systemctl show tg-max-bridge.service -p ExecMainStartTimestamp --value)
logs=$(journalctl -u tg-max-bridge.service --since "$started" --no-pager -o cat)
test "$(printf '%s\n' "$logs" | grep -c 'Application started')" -ge 1
test "$(printf '%s\n' "$logs" | grep -Eic \
  'traceback|conflict.*getupdates|(^|[^a-z])error([^a-z]|$)' || true)" = 0
test "$(printf '%s\n' "$logs" | grep -c 'HTTP Request:' || true)" = 0

token=$(cd "$app_dir" && .venv/bin/python -c \
  'from dotenv import dotenv_values; print(dotenv_values(".env")["BOT_TOKEN"])')
test -n "$token"
if printf '%s\n' "$logs" | grep -Fq "$token"; then
  exit 1
fi

cd "$app_dir"
.venv/bin/python -m unittest discover -s tests >/dev/null
.venv/bin/python -c \
  'import json; json.load(open("max_session.json", encoding="utf-8"))'

printf 'release_head=%s\n' "$expected_head"
printf 'release_dirty=0\n'
printf 'service_active=active\n'
printf 'service_restarts=0\n'
printf 'deployment_unit_matches_git=yes\n'
printf 'runtime_modes=secure\n'
printf 'current_log_bytes=%s\n' "$current_log_size"
printf 'post_start_error_lines=0\n'
printf 'post_start_http_request_lines=0\n'
printf 'secret_in_post_start_logs=no\n'
printf 'runtime_backup_present=yes\n'
