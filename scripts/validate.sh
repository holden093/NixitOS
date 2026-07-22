#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly repo_root
cd "$repo_root"

for check in shell policy containerfile; do
  bash "scripts/validate/${check}.sh"
done

if [[ ${ARIAOS_TEST_WITH_SUDO:-0} == 1 ]]; then
  sudo --non-interactive env ARIAOS_TEST_DIRECT_ROOT=1 bash tests/operational.sh
else
  bash tests/operational.sh
fi

git diff --check
echo "Static validation passed."
