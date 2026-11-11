#!/usr/bin/env bash
set -euo pipefail

release=/opt/crm-releases/5e9556a
node_probe=/root/verify-crm-upload-write.cjs

test "$(readlink -f /opt/crm-current)" = "$release"
test -f "$node_probe"

docker cp "$node_probe" crm-api-1:/app/apps/api/verify-crm-upload-write.cjs >/dev/null
probe_output=$(docker exec -w /app/apps/api crm-api-1 \
  node verify-crm-upload-write.cjs)
storage_path=$(printf '%s\n' "$probe_output" \
  | sed -n 's/^storage_path=//p')
expected_hash=$(printf '%s\n' "$probe_output" \
  | sed -n 's/^sha256=//p')

case "$storage_path" in
  /app/uploads/clients/*.txt) ;;
  *) exit 1 ;;
esac
test -n "$expected_hash"

cd "$release"
docker compose -p crm --env-file .env.production \
  -f docker-compose.prod.yml up -d --no-deps --force-recreate api \
  --wait --wait-timeout 180

test "$(docker inspect --format '{{.State.Health.Status}}' crm-api-1)" = healthy
test "$(docker inspect --format '{{.RestartCount}}' crm-api-1)" = 0
docker exec crm-api-1 test -f "$storage_path"
actual_hash=$(docker exec crm-api-1 sha256sum "$storage_path" \
  | awk '{print $1}')
test "$actual_hash" = "$expected_hash"

docker exec crm-api-1 rm -f "$storage_path"
if docker exec crm-api-1 test -e "$storage_path"; then
  exit 1
fi

printf 'api_health=healthy\n'
printf 'file_hash_preserved=%s\n' "$actual_hash"
printf 'test_file_removed=yes\n'
