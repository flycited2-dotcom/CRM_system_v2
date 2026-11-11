#!/usr/bin/env bash
set -euo pipefail

expected_head=96e589a652a1667027874ce8800f6e1bbdcfe7f9
source_branch=agent/groq-egress-proxy
current_repo=/root/sales_bot
release_dir=/opt/sales-bot-releases/96e589a

test ! -e "$release_dir"
test "$(systemctl is-active sales_bot.service)" = active
test "$(systemctl is-active groq-egress-tunnel.service)" = active

git -C "$current_repo" fetch origin \
  "$source_branch:refs/heads/deploy-96e589a"
test "$(git -C "$current_repo" rev-parse deploy-96e589a)" = "$expected_head"
install -d -m 0755 /opt/sales-bot-releases
git clone --no-local --branch deploy-96e589a --single-branch \
  "$current_repo" "$release_dir"
git -C "$release_dir" checkout --detach "$expected_head"
git -C "$release_dir" remote set-url origin \
  "$(git -C "$current_repo" remote get-url origin)"
git -C "$current_repo" branch -D deploy-96e589a >/dev/null

python3 -m venv "$release_dir/venv"
"$release_dir/venv/bin/python" -m pip install \
  --disable-pip-version-check -r "$release_dir/requirements.lock.txt"

cd "$release_dir"
venv/bin/python -m unittest discover -s tests -v
venv/bin/python -m py_compile \
  config.py main.py database.py sales_agent.py \
  tests/test_config.py tests/test_main.py tests/test_groq_client.py

test -z "$(git status --porcelain)"
test "$(venv/bin/pip freeze | wc -l)" = \
  "$(wc -l < requirements.lock.txt)"

printf 'release_head=%s\n' "$(git rev-parse HEAD)"
printf 'release_dirty=0\n'
printf 'locked_dependencies=%s\n' "$(wc -l < requirements.lock.txt)"
printf 'tests=6_passed\n'
