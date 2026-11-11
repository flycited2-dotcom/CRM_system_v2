#!/usr/bin/env bash
set -euo pipefail

expected_head=5e9556a6ba846d9ba79ae01a986e0ae4fb5b2b22
source_branch=fix/production-runtime-safety
current_release=/opt/crm-releases/6aa76d3
release_dir=/opt/crm-releases/5e9556a
build_project=crm_release_5e9556a
production_project=crm

rollback() {
  local original_code=$?
  trap - ERR
  set +e
  docker image tag crm-api:pre-5e9556a crm-api:latest
  docker image tag crm-web:pre-5e9556a crm-web:latest
  cd "$current_release"
  CRM_HTTP_PORT=8080 docker compose -p "$production_project" \
    -f docker-compose.prod.yml up -d --no-build --remove-orphans
  exit "$original_code"
}

test ! -e "$release_dir"
git -C "$current_release" fetch origin \
  "$source_branch:refs/heads/deploy-5e9556a"
test "$(git -C "$current_release" rev-parse deploy-5e9556a)" = "$expected_head"
git clone --no-local --branch deploy-5e9556a --single-branch \
  "$current_release" "$release_dir"
git -C "$release_dir" checkout --detach "$expected_head"
git -C "$release_dir" remote set-url origin \
  "$(git -C "$current_release" remote get-url origin)"
git -C "$current_release" branch -D deploy-5e9556a >/dev/null
test -z "$(git -C "$release_dir" status --porcelain)"

install -m 0600 "$current_release/.env.production" \
  "$release_dir/.env.production"

python3 - "$release_dir/.env.production" "$release_dir/.env" <<'PY'
from pathlib import Path
import re
import sys

production_path = Path(sys.argv[1])
compose_path = Path(sys.argv[2])
updates = {
    "CLIENT_UPLOAD_DIR": "/app/uploads/clients",
    "CRM_HTTP_PORT": "8080",
    "WEB_ORIGIN": "http://212.116.115.150:8080",
}

lines = production_path.read_text(encoding="utf-8").splitlines(keepends=True)
for key, value in updates.items():
    replacement = f'{key}="{value}"\n'
    pattern = re.compile(rf"^{re.escape(key)}=")
    indexes = [index for index, line in enumerate(lines) if pattern.match(line)]
    if indexes:
        lines[indexes[-1]] = replacement
        for index in reversed(indexes[:-1]):
            del lines[index]
    else:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append(replacement)

production_path.write_text("".join(lines), encoding="utf-8")
compose_path.write_text('CRM_HTTP_PORT="8080"\n', encoding="utf-8")
PY

chmod 0600 "$release_dir/.env.production" "$release_dir/.env"

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

printf 'release_head=%s\n' "$(git rev-parse HEAD)"
printf 'healthy_services=5\n'
printf 'health_body=%s\n' "$health_body"
