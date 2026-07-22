#!/usr/bin/env bash
set -Eeuo pipefail

readonly image_sources=(Containerfile build_files scripts/build versions)

if rg -n '(^|/)(var/home/kevin|home/kevin)|\bkevin\b' "${image_sources[@]}"; then
  echo "User-specific path or account found in the image definition." >&2
  exit 1
fi

readonly removed_model_pattern='aria-gguf-engine|llama\.cpp|/var/llms|\bddgs\b'
removed_model_matches=$(
  rg -n -i "$removed_model_pattern" "${image_sources[@]}" |
    rg -v 'rm -rf /usr/share/aria /usr/share/aria-gguf-engine' || true
)
if [[ -n $removed_model_matches ]]; then
  printf '%s\n' "$removed_model_matches"
  echo "Removed local-model component found in the image definition." >&2
  exit 1
fi

readonly blacklist=build_files/etc/modprobe.d/blacklist-nvidia.conf
for module in nvidia nvidia_uvm nouveau nvidia_modeset nvidia_drm; do
  if ! grep -Fqx "install $module /bin/false" "$blacklist"; then
    echo "Invalid on-demand NVIDIA policy for module: $module" >&2
    exit 1
  fi
done
