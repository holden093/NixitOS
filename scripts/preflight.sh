#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image_tag=${ARIAOS_PREFLIGHT_IMAGE:-localhost/ariaos-preflight:test}
start_time=$(date +%s)

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ ${ARIAOS_KEEP_PREFLIGHT_IMAGE:-0} != 1 ]]; then
    podman image rm -f "$image_tag" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

cd "$repo_root"
echo "AriaOS preflight"
echo "Repository: $repo_root"
echo "Image:      $image_tag"
echo

./scripts/validate.sh
echo

mapfile -t changed_files < <(
  git diff --name-only HEAD -- Containerfile build_files scripts/build versions
)
if (( ${#changed_files[@]} > 0 )); then
  echo "Image-affecting changes:"
  printf '  %s\n' "${changed_files[@]}"
  echo
fi

podman build --pull=missing -f Containerfile -t "$image_tag" .
./scripts/validate/image.sh "$image_tag"

duration=$(( $(date +%s) - start_time ))
echo
echo "Preflight passed in ${duration}s."
