#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

for check in shell policy containerfile; do
  bash "scripts/validate/${check}.sh"
done

bash tests/operational.sh

git diff --check
echo "Static validation passed."
