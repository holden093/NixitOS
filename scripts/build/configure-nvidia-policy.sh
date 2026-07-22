#!/usr/bin/env bash
set -Eeuo pipefail

readonly inherited_policy_files=(
  /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
  /usr/lib/modprobe.d/nvidia-modeset.conf
  /usr/lib/modprobe.d/nvidia.conf
  /usr/lib/bootc/kargs.d/bluebuild-kargs.toml
)
readonly masked_units=(
  nvidia-hibernate.service
  nvidia-resume.service
  nvidia-suspend.service
  nvidia-suspend-then-hibernate.service
  nvidia-powerd.service
  nvidia-persistenced.service
)

rm -f "${inherited_policy_files[@]}"
systemctl mask "${masked_units[@]}"

readonly blacklist=/etc/modprobe.d/blacklist-nvidia.conf
for module in nvidia nvidia_uvm nouveau nvidia_modeset nvidia_drm; do
  if ! grep -Fqx "install $module /bin/false" "$blacklist"; then
    echo "Missing explicit on-demand NVIDIA policy for module: $module" >&2
    exit 1
  fi
done

echo "AriaOS: NVIDIA is now on-demand only."
