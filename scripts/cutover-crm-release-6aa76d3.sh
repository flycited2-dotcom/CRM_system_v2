#!/usr/bin/env bash
set -euo pipefail

release_dir=/opt/crm-releases/6aa76d3
old_dir=/opt/crm
candidate_project=crm_candidate_6aa76d3
production_project=crm
backup_dir=/root/crm-migration-backups/20260719-before-6aa76d3
export CRM_HTTP_PORT=8080

wait_for_health() {
  local attempt code
  for attempt in $(seq 1 36); do
    code=$(curl -sS -o /tmp/crm-production-health.json -w '%{http_code}' \
      http://127.0.0.1:8080/api/health || true)
    if [[ "$code" == 200 ]]; then
      return 0
    fi
    sleep 5
  done
  return 1
}

rollback() {
  local original_code=$?
  trap - ERR
  set +e
  echo 'cutover_failed=true; restoring previous images and compose definition'
  docker image tag crm-api:pre-6aa76d3 crm-api:latest
  docker image tag crm-web:pre-6aa76d3 crm-web:latest
  cd "$old_dir"
  docker compose -p "$production_project" -f docker-compose.migration.yml \
    up -d --no-build --remove-orphans
  wait_for_health
  echo "rollback_health=$?"
  exit "$original_code"
}

test "$(git -C "$release_dir" rev-parse HEAD)" = \
  6aa76d3389ff9499a87d262082a7217a45fd759d
test -f "$backup_dir/crm-before-6aa76d3.pgcustom"
test -f "$backup_dir/crm-source-before-6aa76d3.tar.gz"
docker image inspect crm_candidate_6aa76d3-api:latest >/dev/null
docker image inspect crm_candidate_6aa76d3-web:latest >/dev/null

docker image tag "$(docker inspect --format '{{.Image}}' crm-api-1)" \
  crm-api:pre-6aa76d3
docker image tag "$(docker inspect --format '{{.Image}}' crm-web-1)" \
  crm-web:pre-6aa76d3
docker image tag crm_candidate_6aa76d3-api:latest crm-api:6aa76d3
docker image tag crm_candidate_6aa76d3-web:latest crm-web:6aa76d3

cd "$release_dir"
docker compose -p "$candidate_project" -f docker-compose.prod.yml down

trap rollback ERR
docker image tag crm-api:6aa76d3 crm-api:latest
docker image tag crm-web:6aa76d3 crm-web:latest
docker compose -p "$production_project" -f docker-compose.prod.yml \
  up -d --no-build --remove-orphans
wait_for_health
docker compose -p "$production_project" -f docker-compose.prod.yml \
  exec -T api npm run prisma:seed

health_body=$(cat /tmp/crm-production-health.json)
test "$health_body" = '{"status":"ok","service":"crm-api"}'

printf 'schema_migrations='
docker exec crm-postgres-1 sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM \"_prisma_migrations\" WHERE finished_at IS NOT NULL"'
printf 'running_services='
docker ps --filter label=com.docker.compose.project=crm \
  --filter status=running --format '{{.Names}}' | wc -l
printf 'production_health=200\n'
printf 'release_head='
git rev-parse HEAD

trap - ERR
