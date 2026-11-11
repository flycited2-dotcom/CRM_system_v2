#!/usr/bin/env bash
set -euo pipefail

expected_head=5e9556a6ba846d9ba79ae01a986e0ae4fb5b2b22
release_dir=/opt/crm-releases/5e9556a
build_project=crm_release_5e9556a
production_project=crm

rollback() {
  local original_code=$?
  trap - ERR
  set +e
  docker image tag crm-api:pre-5e9556a crm-api:latest
  docker image tag crm-web:pre-5e9556a crm-web:latest
  cd "$release_dir"
  docker compose -p "$production_project" --env-file .env.production \
    -f docker-compose.prod.yml up -d --no-build --remove-orphans
  exit "$original_code"
}

test "$(git -C "$release_dir" rev-parse HEAD)" = "$expected_head"
test -z "$(git -C "$release_dir" status --porcelain)"
test "$(readlink -f /opt/crm-current)" = /opt/crm-releases/6aa76d3
test -f /root/crm-migration-backups/20260719-before-5e9556a/crm-before-5e9556a.pgcustom

cd "$release_dir"
docker compose -p "$build_project" --env-file .env.production \
  -f docker-compose.prod.yml config --quiet
docker compose -p "$build_project" --env-file .env.production \
  -f docker-compose.prod.yml build api web

docker image tag "$(docker inspect --format '{{.Image}}' crm-api-1)" \
  crm-api:pre-5e9556a
docker image tag "$(docker inspect --format '{{.Image}}' crm-web-1)" \
  crm-web:pre-5e9556a
docker image tag "$build_project-api:latest" crm-api:5e9556a
docker image tag "$build_project-web:latest" crm-web:5e9556a

trap rollback ERR
docker image tag crm-api:5e9556a crm-api:latest
docker image tag crm-web:5e9556a crm-web:latest
docker compose -p "$production_project" --env-file .env.production \
  -f docker-compose.prod.yml up -d --no-build --force-recreate \
  --remove-orphans --wait --wait-timeout 240

health_body=$(curl -fsS http://127.0.0.1:8080/api/health)
test "$health_body" = '{"status":"ok","service":"crm-api"}'
test "$(docker ps --filter label=com.docker.compose.project=crm \
  --filter health=healthy --format '{{.Names}}' | wc -l)" = 5

ln -sfn "$release_dir" /opt/crm-current
test "$(readlink -f /opt/crm-current)" = "$release_dir"
test -z "$(git status --porcelain)"
git -C /opt/crm-releases/6aa76d3 branch -D deploy-5e9556a >/dev/null 2>&1 || true

printf 'release_head=%s\n' "$(git rev-parse HEAD)"
printf 'healthy_services=5\n'
printf 'health_body=%s\n' "$health_body"
