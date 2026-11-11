#!/usr/bin/env bash
set -euo pipefail

release=/opt/crm-releases/5e9556a
expected_head=5e9556a6ba846d9ba79ae01a986e0ae4fb5b2b22

test "$(readlink -f /opt/crm-current)" = "$release"
test "$(git -C "$release" rev-parse HEAD)" = "$expected_head"
test -z "$(git -C "$release" status --porcelain)"

printf 'release_head=%s\n' "$expected_head"
printf 'release_dirty=0\n'

for container in crm-nginx-1 crm-web-1 crm-api-1 crm-postgres-1 crm-redis-1; do
  health=$(docker inspect --format '{{.State.Health.Status}}' "$container")
  restarts=$(docker inspect --format '{{.RestartCount}}' "$container")
  working_dir=$(docker inspect --format \
    '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' \
    "$container")
  test "$health" = healthy
  test "$restarts" = 0
  test "$working_dir" = "$release"
  printf 'container=%s health=%s restarts=%s working_dir=%s\n' \
    "$container" "$health" "$restarts" "$working_dir"
done

test "$(docker inspect --format '{{.Image}}' crm-api-1)" = \
  "$(docker image inspect --format '{{.Id}}' crm-api:5e9556a)"
test "$(docker inspect --format '{{.Image}}' crm-web-1)" = \
  "$(docker image inspect --format '{{.Id}}' crm-web:5e9556a)"
printf 'release_images=matched\n'

health_body=$(curl -fsS http://127.0.0.1:8080/api/health)
test "$health_body" = '{"status":"ok","service":"crm-api"}'
printf 'health_body=%s\n' "$health_body"

test "$(docker exec crm-api-1 printenv CLIENT_UPLOAD_DIR)" = \
  /app/uploads/clients
printf 'client_upload_dir=/app/uploads/clients\n'

cd "$release"
published_port=$(docker compose -p crm -f docker-compose.prod.yml config \
  | awk '/published:/ { print $2; exit }' | tr -d '"')
test "$published_port" = 8080
printf 'compose_default_port=%s\n' "$published_port"

docker exec crm-postgres-1 sh -c \
  'printf "schema_migrations="; psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM \"_prisma_migrations\" WHERE finished_at IS NOT NULL"; printf "users="; psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM users"; printf "clients="; psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM clients"; printf "leads="; psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM leads"'

test "$(docker exec crm-redis-1 redis-cli ping)" = PONG
printf 'redis_ping=PONG\n'

uploads_count=$(docker exec crm-api-1 sh -c \
  'if [ -d /app/uploads/clients ]; then find /app/uploads/clients -type f | wc -l; else echo 0; fi')
printf 'client_upload_files=%s\n' "$uploads_count"

for container in crm-nginx-1 crm-web-1 crm-api-1 crm-postgres-1 crm-redis-1; do
  errors=$(docker logs "$container" 2>&1 \
    | grep -Eic 'fatal|panic|unhandled|exception|(^|[^a-z])error([^a-z]|$)' || true)
  printf 'container=%s error_lines=%s\n' "$container" "$errors"
done

candidate_containers=$((
  $(docker ps -a --filter label=com.docker.compose.project=crm_runtime_safety \
    --format '{{.Names}}' | wc -l) +
  $(docker ps -a --filter label=com.docker.compose.project=crm_candidate_6aa76d3 \
    --format '{{.Names}}' | wc -l)
))
candidate_volumes=$((
  $(docker volume ls --filter label=com.docker.compose.project=crm_runtime_safety \
    --format '{{.Name}}' | wc -l) +
  $(docker volume ls --filter label=com.docker.compose.project=crm_candidate_6aa76d3 \
    --format '{{.Name}}' | wc -l)
))
test "$candidate_containers" = 0
test "$candidate_volumes" = 0
printf 'candidate_containers=0\n'
printf 'candidate_volumes=0\n'

test -s /root/crm-migration-backups/20260719-before-5e9556a/crm-before-5e9556a.pgcustom
test -s /root/crm-migration-backups/20260719-before-5e9556a/uploads-before-5e9556a.tar.gz
printf 'predeploy_backup_present=yes\n'
