#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for file in build.sh sb.sh lib/*.sh tests/*.sh; do bash -n "$file"; done
bash tests/reliability.sh
bash tests/migration.sh
bash tests/export.sh
check_tmp="$(mktemp -d)"
trap 'rm -rf "$check_tmp"' EXIT
cp -R lib build.sh "$check_tmp/"
bash "$check_tmp/build.sh"
cmp sb.sh "$check_tmp/sb.sh"
