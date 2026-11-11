#!/usr/bin/env bash
set -euo pipefail

backup_dir=/root/crm-migration-backups/20260719-before-5e9556a
release_dir=/opt/crm-releases/6aa76d3
postgres_container=crm-postgres-1
redis_container=crm-redis-1

install -d -m 0700 "$backup_dir"

docker exec "$postgres_container" sh -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > "$backup_dir/crm-before-5e9556a.pgcustom"
docker exec "$postgres_container" sh -c \
  'pg_dumpall -U "$POSTGRES_USER" --globals-only' \
  > "$backup_dir/postgres-globals-before-5e9556a.sql"

docker cp "$backup_dir/crm-before-5e9556a.pgcustom" \
  "$postgres_container:/tmp/crm-before-5e9556a.pgcustom" >/dev/null
docker exec "$postgres_container" \
  pg_restore --list /tmp/crm-before-5e9556a.pgcustom >/dev/null
docker exec "$postgres_container" rm -f /tmp/crm-before-5e9556a.pgcustom

docker exec "$redis_container" redis-cli SAVE >/dev/null
docker cp "$redis_container:/data/dump.rdb" \
  "$backup_dir/redis-before-5e9556a.rdb" >/dev/null

docker run --rm --entrypoint sh \
  -v crm_crm_uploads:/data:ro \
  -v "$backup_dir:/backup" \
  nginx:1.27-alpine \
  -c 'tar -C /data -czf /backup/uploads-before-5e9556a.tar.gz .'

tar --exclude='./.git' \
  -C "$release_dir" \
  -czf "$backup_dir/crm-release-6aa76d3-source-and-config.tar.gz" .

tar -tzf "$backup_dir/uploads-before-5e9556a.tar.gz" >/dev/null
tar -tzf "$backup_dir/crm-release-6aa76d3-source-and-config.tar.gz" >/dev/null
chmod 0600 "$backup_dir"/*

(cd "$backup_dir" && sha256sum \
  crm-before-5e9556a.pgcustom \
  postgres-globals-before-5e9556a.sql \
  redis-before-5e9556a.rdb \
  uploads-before-5e9556a.tar.gz \
  crm-release-6aa76d3-source-and-config.tar.gz)
