#!/usr/bin/env bash
set -Eeuo pipefail

# AriaOS: policy NVIDIA compute-only.
# La eGPU resta non inizializzata a boot: solo ariaos-egpu.service carica i
# moduli di calcolo (nvidia, nvidia_uvm) quando serve il calcolo CUDA.

readonly inherited_policy_files=(
  /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
  /usr/lib/modprobe.d/nvidia-modeset.conf
  /usr/lib/modprobe.d/nvidia.conf
  /usr/lib/bootc/kargs.d/bluebuild-kargs.toml
)
readonly inherited_udev_rules=(
  /usr/lib/udev/rules.d/80-nvidia-driver.rules
  /usr/lib/udev/rules.d/80-nvidia-persistenced.rules
)
readonly masked_units=(
  nvidia-hibernate.service
  nvidia-resume.service
  nvidia-suspend.service
  nvidia-suspend-then-hibernate.service
  nvidia-powerd.service
  nvidia-persistenced.service
  nvidia-cdi-refresh.service
  nvidia-cdi-refresh.path
)

rm -f "${inherited_policy_files[@]}"
rm -f "${inherited_udev_rules[@]}"
systemctl mask "${masked_units[@]}"

readonly blacklist=/etc/modprobe.d/blacklist-nvidia.conf
for module in nvidia_drm nvidia_modeset nouveau; do
  if ! grep -Fqx "install $module /bin/false" "$blacklist"; then
    echo "Missing permanent display-off policy for module: $module" >&2
    exit 1
  fi
done
for module in nvidia nvidia_uvm; do
  if grep -Fqx "install $module /bin/false" "$blacklist"; then
    echo "Compute module $module must stay on-demand, not hard-blocked." >&2
    exit 1
  fi
done
if ! grep -Fq 'nvidia-drm.modeset=0' /usr/lib/bootc/kargs.d/ariaos-blacklist.toml; then
  echo "Missing nvidia-drm.modeset=0 karg." >&2
  exit 1
fi

echo "AriaOS: NVIDIA policy is compute-only, on-demand."
