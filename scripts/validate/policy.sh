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
  echo "Local-model component found in the host image definition (guest/ only)." >&2
  exit 1
fi

if rg -n 'egpu-up|egpu-down|configure-nvidia-policy' "${image_sources[@]}" tests; then
  echo "Retired on-demand NVIDIA component still referenced." >&2
  exit 1
fi

readonly blacklist=build_files/etc/modprobe.d/blacklist-nvidia.conf
for module in nvidia nvidia_uvm nouveau nvidia_modeset nvidia_drm; do
  if ! grep -Fqx "install $module /bin/false" "$blacklist"; then
    echo "Invalid complete NVIDIA blacklist policy for module: $module" >&2
    exit 1
  fi
done

readonly vfio_kargs=build_files/usr/lib/bootc/kargs.d/ariaos-vfio.toml
for karg in 'vfio-pci.ids=10de:2504,10de:228e' 'pcie_acs_override=downstream' 'intel_iommu=on' 'iommu=pt'; do
  if ! grep -Fq "$karg" "$vfio_kargs"; then
    echo "Missing VFIO karg in $vfio_kargs: $karg" >&2
    exit 1
  fi
done

readonly vfio_udev=build_files/usr/lib/udev/rules.d/69-ariaos-vfio.rules
for device in 0x2504 0x228e; do
  if ! grep -Fq "ATTRS{device}==\"$device\"" "$vfio_udev"; then
    echo "Missing vfio driver_override rule for device $device." >&2
    exit 1
  fi
done

if ! grep -Fq 'virtqemud.socket' scripts/build/configure-services.sh; then
  echo "Missing virtqemud.socket enablement in configure-services.sh." >&2
  exit 1
fi

if ! grep -Eq '^v /var/vms ' build_files/usr/lib/tmpfiles.d/ariaos-subvols.conf; then
  echo "Missing /var/vms subvolume declaration." >&2
  exit 1
fi

echo "Image contract policy passed."
