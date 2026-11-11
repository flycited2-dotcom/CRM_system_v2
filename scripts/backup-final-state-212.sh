#!/usr/bin/env bash
set -euo pipefail
umask 077

backup_dir=/root/migration-backups/final-state-20260719
crm_release=/opt/crm-releases/5e9556a
sales_release=/opt/sales-bot-releases/96e589a
tgmax_dir=/opt/tg-max-bridge

test "$(readlink -f /opt/crm-current)" = "$crm_release"
test "$(readlink -f /opt/sales-bot-current)" = "$sales_release"
test "$(systemctl is-active sales_bot.service)" = active
test "$(systemctl is-active tg-max-bridge.service)" = active

install -d -m 0700 "$backup_dir"

docker exec crm-postgres-1 sh -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > "$backup_dir/crm-final.pgcustom"
docker exec crm-postgres-1 sh -c \
  'pg_dumpall -U "$POSTGRES_USER" --globals-only' \
  > "$backup_dir/crm-postgres-globals-final.sql"
docker cp "$backup_dir/crm-final.pgcustom" \
  crm-postgres-1:/tmp/crm-final.pgcustom >/dev/null
docker exec crm-postgres-1 pg_restore --list /tmp/crm-final.pgcustom >/dev/null
docker exec crm-postgres-1 rm -f /tmp/crm-final.pgcustom

docker exec crm-redis-1 redis-cli SAVE >/dev/null
docker cp crm-redis-1:/data/dump.rdb "$backup_dir/crm-redis-final.rdb" >/dev/null
docker run --rm --entrypoint sh \
  -v crm_crm_uploads:/data:ro \
  -v "$backup_dir:/backup" \
  nginx:1.27-alpine \
  -c 'tar -C /data -czf /backup/crm-uploads-final.tar.gz .'
tar -C "$crm_release" -czf "$backup_dir/crm-config-final.tar.gz" \
  .env .env.production

install -m 0600 "$sales_release/.env" "$backup_dir/sales-final.env"
install -m 0600 /var/lib/sales-bot/sales.db "$backup_dir/sales-final.db"
install -m 0600 /var/lib/sales-bot/products.json \
  "$backup_dir/sales-products-final.json"
install -m 0644 /etc/systemd/system/sales_bot.service \
  "$backup_dir/sales_bot-final.service"
install -m 0644 /etc/systemd/system/sales_bot.service.d/groq-egress.conf \
  "$backup_dir/sales_bot-groq-final.conf"
test "$(sqlite3 -readonly "$backup_dir/sales-final.db" 'PRAGMA integrity_check;')" = ok

install -m 0644 /etc/systemd/system/tg-max-bridge.service \
  "$backup_dir/tg-max-bridge-final.service"
tar -C "$tgmax_dir" -czf "$backup_dir/tg-max-runtime-final.tar.gz" \
  .env max_session.json bridge.log bridge.log.1 debug
python3 - "$tgmax_dir/max_session.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
if not isinstance(payload, dict):
    raise SystemExit(1)
PY

tar -tzf "$backup_dir/crm-uploads-final.tar.gz" >/dev/null
tar -tzf "$backup_dir/crm-config-final.tar.gz" >/dev/null
tar -tzf "$backup_dir/tg-max-runtime-final.tar.gz" >/dev/null
chmod 0600 "$backup_dir"/*

(cd "$backup_dir" && sha256sum \
  crm-final.pgcustom \
  crm-postgres-globals-final.sql \
  crm-redis-final.rdb \
  crm-uploads-final.tar.gz \
  crm-config-final.tar.gz \
  sales-final.env \
  sales-final.db \
  sales-products-final.json \
  sales_bot-final.service \
  sales_bot-groq-final.conf \
  tg-max-bridge-final.service \
  tg-max-runtime-final.tar.gz \
  > SHA256SUMS.txt)

printf 'manifest_entries=%s\n' "$(wc -l < "$backup_dir/SHA256SUMS.txt")"
printf 'sales_sqlite_integrity=ok\n'
printf 'crm_dump_restore_list=ok\n'
printf 'archives_readable=ok\n'
