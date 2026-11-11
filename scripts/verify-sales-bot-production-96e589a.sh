#!/usr/bin/env bash
set -euo pipefail

release=/opt/sales-bot-releases/96e589a
expected_head=96e589a652a1667027874ce8800f6e1bbdcfe7f9
data_dir=/var/lib/sales-bot
backup_dir=/root/migration-backups/sales-bot/20260719-before-96e589a

test "$(readlink -f /opt/sales-bot-current)" = "$release"
test "$(git -C "$release" rev-parse HEAD)" = "$expected_head"
test -z "$(git -C "$release" status --porcelain)"
test "$(systemctl is-active sales_bot.service)" = active
test "$(systemctl is-enabled sales_bot.service)" = enabled
test "$(systemctl show sales_bot.service -p NRestarts --value)" = 0
test "$(systemctl show sales_bot.service -p ExecMainStatus --value)" = 0
test "$(systemctl is-active groq-egress-tunnel.service)" = active
test "$(systemctl show groq-egress-tunnel.service -p NRestarts --value)" = 0

cmp -s "$release/deploy/sales_bot.service" \
  /etc/systemd/system/sales_bot.service
cmp -s "$release/deploy/sales_bot-groq-egress.conf" \
  /etc/systemd/system/sales_bot.service.d/groq-egress.conf

test "$(stat -c %a "$release/.env")" = 600
test "$(stat -c %a "$data_dir/sales.db")" = 600
test "$(stat -c %a "$data_dir/products.json")" = 600
test "$(sqlite3 -readonly "$data_dir/sales.db" 'PRAGMA integrity_check;')" = ok

data_path=$(cd "$release" && venv/bin/python -c \
  'import config; print(config.SALES_DATA_DIR)')
test "$data_path" = "$data_dir"
products=$(cd "$release" && venv/bin/python -c \
  'from database import reload_products; print(len(reload_products()))')
test "$products" = 2357

started=$(systemctl show sales_bot.service -p ExecMainStartTimestamp --value)
logs=$(journalctl -u sales_bot.service --since "$started" --no-pager -o cat)
test "$(printf '%s\n' "$logs" | grep -c 'Bot @')" -ge 1
test "$(printf '%s\n' "$logs" | grep -Eic \
  'traceback|conflict.*getupdates|groq.*403|403.*groq|(^|[^a-z])error([^a-z]|$)' || true)" = 0
test "$(printf '%s\n' "$logs" | grep -c 'HTTP Request:' || true)" = 0

token=$(cd "$release" && venv/bin/python -c \
  'from dotenv import dotenv_values; print(dotenv_values(".env")["TELEGRAM_BOT_TOKEN"])')
test -n "$token"
if printf '%s\n' "$logs" | grep -Fq "$token"; then
  exit 1
fi

test -s "$backup_dir/sales.db"
test -s "$backup_dir/products.json"

printf 'release_head=%s\n' "$expected_head"
printf 'release_dirty=0\n'
printf 'service_active=active\n'
printf 'service_restarts=0\n'
printf 'tunnel_active=active\n'
printf 'tunnel_restarts=0\n'
printf 'sqlite_integrity=ok\n'
printf 'conversations=%s\n' \
  "$(sqlite3 -readonly "$data_dir/sales.db" 'SELECT COUNT(*) FROM conversations;')"
printf 'orders=%s\n' \
  "$(sqlite3 -readonly "$data_dir/sales.db" 'SELECT COUNT(*) FROM orders;')"
printf 'products=%s\n' "$products"
printf 'post_start_error_lines=0\n'
printf 'post_start_http_request_lines=0\n'
printf 'secret_in_post_start_logs=no\n'
printf 'deployment_files_match_git=yes\n'
printf 'backup_present=yes\n'
