#!/usr/bin/env bash
set -euo pipefail

backup_dir=/root/crm-migration-backups/20260719-before-6aa76d3
postgres_container=crm-postgres-1
redis_container=crm-redis-1

install -d -m 0700 "$backup_dir"

docker exec "$postgres_container" sh -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > "$backup_dir/crm-before-6aa76d3.pgcustom"
docker exec "$postgres_container" sh -c \
  'pg_dumpall -U "$POSTGRES_USER" --globals-only' \
  > "$backup_dir/postgres-globals-before-6aa76d3.sql"

docker cp "$backup_dir/crm-before-6aa76d3.pgcustom" \
  "$postgres_container:/tmp/crm-before-6aa76d3.pgcustom" >/dev/null
docker exec "$postgres_container" \
  pg_restore --list /tmp/crm-before-6aa76d3.pgcustom >/dev/null
docker exec "$postgres_container" rm -f /tmp/crm-before-6aa76d3.pgcustom

docker exec "$redis_container" redis-cli SAVE >/dev/null
docker cp "$redis_container:/data/dump.rdb" \
  "$backup_dir/redis-before-6aa76d3.rdb" >/dev/null

tar --exclude='./node_modules' --exclude='./apps/api/node_modules' \
  --exclude='./apps/web/node_modules' \
  -C /opt -czf "$backup_dir/crm-source-before-6aa76d3.tar.gz" crm
tar -tzf "$backup_dir/crm-source-before-6aa76d3.tar.gz" >/dev/null

chmod 0600 "$backup_dir"/*

printf 'schema_migrations='
docker exec "$postgres_container" sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM \"_prisma_migrations\" WHERE finished_at IS NOT NULL"'
printf 'users='
docker exec "$postgres_container" sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM users"'
printf 'work_sessions='
docker exec "$postgres_container" sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM work_sessions"'
printf 'redis_keys='
docker exec "$redis_container" redis-cli DBSIZE | sed 's/^dbsize: //'

(cd "$backup_dir" && sha256sum \
  crm-before-6aa76d3.pgcustom \
  postgres-globals-before-6aa76d3.sql \
  redis-before-6aa76d3.rdb \
  crm-source-before-6aa76d3.tar.gz)
