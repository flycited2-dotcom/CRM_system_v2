#!/usr/bin/env bash
set -euo pipefail
umask 077

expected_head=96e589a652a1667027874ce8800f6e1bbdcfe7f9
release_dir=/opt/sales-bot-releases/96e589a
current_dir=/root/sales_bot
data_dir=/var/lib/sales-bot
backup_dir=/root/migration-backups/sales-bot/20260719-before-96e589a
unit=/etc/systemd/system/sales_bot.service
dropin=/etc/systemd/system/sales_bot.service.d/groq-egress.conf

rollback() {
  local original_code=$?
  trap - ERR
  set +e
  systemctl stop sales_bot.service
  install -m 0644 "$backup_dir/sales_bot.service" "$unit"
  install -d -m 0755 /etc/systemd/system/sales_bot.service.d
  install -m 0644 "$backup_dir/groq-egress.conf" "$dropin"
  systemctl daemon-reload
  systemctl start sales_bot.service
  exit "$original_code"
}

test "$(git -C "$release_dir" rev-parse HEAD)" = "$expected_head"
test -z "$(git -C "$release_dir" status --porcelain)"
test "$(systemctl is-active sales_bot.service)" = active
test "$(systemctl is-active groq-egress-tunnel.service)" = active
grep -q '^GROQ_PROXY_URL=socks5://127.0.0.1:11080$' "$current_dir/.env"

install -d -m 0700 "$backup_dir" "$data_dir"
install -m 0644 "$unit" "$backup_dir/sales_bot.service"
install -m 0644 "$dropin" "$backup_dir/groq-egress.conf"

trap rollback ERR
systemctl stop sales_bot.service
test "$(systemctl is-active sales_bot.service || true)" = inactive

test "$(sqlite3 -readonly "$current_dir/data/sales.db" 'PRAGMA integrity_check;')" = ok
source_db_hash=$(sha256sum "$current_dir/data/sales.db" | awk '{print $1}')
source_catalog_hash=$(sha256sum "$current_dir/data/products.json" | awk '{print $1}')

install -m 0600 "$current_dir/.env" "$backup_dir/sales-bot.env"
install -m 0600 "$current_dir/data/sales.db" "$backup_dir/sales.db"
install -m 0600 "$current_dir/data/products.json" "$backup_dir/products.json"
install -m 0600 "$current_dir/data/sales.db" "$data_dir/sales.db"
install -m 0600 "$current_dir/data/products.json" "$data_dir/products.json"
install -m 0600 "$current_dir/.env" "$release_dir/.env"

python3 - "$release_dir/.env" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
key = "SALES_DATA_DIR"
replacement = f'{key}="/var/lib/sales-bot"\n'
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
indexes = [index for index, line in enumerate(lines) if re.match(r"^SALES_DATA_DIR=", line)]
if indexes:
    lines[indexes[-1]] = replacement
    for index in reversed(indexes[:-1]):
        del lines[index]
else:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append(replacement)
path.write_text("".join(lines), encoding="utf-8")
PY

chmod 0600 "$release_dir/.env" "$data_dir/sales.db" "$data_dir/products.json"
test "$(sha256sum "$data_dir/sales.db" | awk '{print $1}')" = "$source_db_hash"
test "$(sha256sum "$data_dir/products.json" | awk '{print $1}')" = "$source_catalog_hash"
test "$(sqlite3 -readonly "$data_dir/sales.db" 'PRAGMA integrity_check;')" = ok

ln -sfn "$release_dir" /opt/sales-bot-current
install -m 0644 "$release_dir/deploy/sales_bot.service" "$unit"
install -d -m 0755 /etc/systemd/system/sales_bot.service.d
install -m 0644 "$release_dir/deploy/sales_bot-groq-egress.conf" "$dropin"
systemctl daemon-reload
systemd-analyze verify sales_bot.service

start_time=$(date --iso-8601=seconds)
systemctl enable sales_bot.service >/dev/null
systemctl start sales_bot.service
sleep 12

test "$(systemctl is-active sales_bot.service)" = active
test "$(systemctl is-enabled sales_bot.service)" = enabled
test "$(systemctl show sales_bot.service -p NRestarts --value)" = 0
test "$(systemctl show sales_bot.service -p ExecMainStatus --value)" = 0
test "$(readlink -f /opt/sales-bot-current)" = "$release_dir"
test -z "$(git -C "$release_dir" status --porcelain)"

logs=$(journalctl -u sales_bot.service --since "$start_time" --no-pager -o cat)
test "$(printf '%s\n' "$logs" | grep -c 'Bot @')" -ge 1
test "$(printf '%s\n' "$logs" | grep -Eic 'traceback|conflict.*getupdates|groq.*403|403.*groq' || true)" = 0
token=$(cd "$release_dir" && venv/bin/python -c \
  'from dotenv import dotenv_values; print(dotenv_values(".env")["TELEGRAM_BOT_TOKEN"])')
test -n "$token"
if printf '%s\n' "$logs" | grep -Fq "$token"; then
  exit 1
fi

test "$(sqlite3 -readonly "$data_dir/sales.db" 'PRAGMA integrity_check;')" = ok
printf 'conversations=%s\n' \
  "$(sqlite3 -readonly "$data_dir/sales.db" 'SELECT COUNT(*) FROM conversations;')"
printf 'orders=%s\n' \
  "$(sqlite3 -readonly "$data_dir/sales.db" 'SELECT COUNT(*) FROM orders;')"
printf 'products=%s\n' \
  "$(cd "$release_dir" && venv/bin/python -c \
    'from database import reload_products; print(len(reload_products()))')"
printf 'release_head=%s\n' "$expected_head"
printf 'service_active=active\n'
printf 'service_restarts=0\n'
printf 'database_sha256=%s\n' "$source_db_hash"
printf 'catalog_sha256=%s\n' "$source_catalog_hash"

(cd "$backup_dir" && sha256sum \
  sales-bot.env sales.db products.json sales_bot.service groq-egress.conf)

trap - ERR
