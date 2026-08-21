#!/usr/bin/env bash
set -Eeuo pipefail

readonly image_sources=(Containerfile build_files scripts/build versions)

if rg -n '(^|/)(var/home/kevin|home/kevin)|\bkevin\b' "${image_sources[@]}"; then
  echo "User-specific path or account found in the image definition." >&2
  exit 1
fi

readonly removed_model_pattern='aria-gguf-engine|/var/llms|\bddgs\b'
removed_model_matches=$(
  rg -n -i "$removed_model_pattern" "${image_sources[@]}" |
    rg -v 'rm -rf /usr/share/aria /usr/share/aria-gguf-engine' || true
)
if [[ -n $removed_model_matches ]]; then
  printf '%s\n' "$removed_model_matches"
  echo "Retired local-model component found in the host image definition." >&2
  exit 1
fi

# Nessun motore di inferenza deve essere installato o costruito nell'immagine:
# l'host fornisce driver, CDI e toolchain; i server vivono in /var/home o in container scelti dall'utente.
if rg -n -i 'install.*\bllama\b|\bgit clone.*llama|copy.*\bllama-server' \
    scripts/build Containerfile; then
  echo "LLM engine installation found in the build definition." >&2
  exit 1
fi
if rg -n '(usr/(s)?bin/|usr/libexec/)(llama|llama-server|llama-cli)' build_files; then
  echo "LLM engine binary found in build_files." >&2
  exit 1
fi

if rg -n 'egpu-up|egpu-down' "${image_sources[@]}" tests; then
  echo "Retired on-demand NVIDIA component still referenced." >&2
  exit 1
fi

if rg -n 'llama-vm|vfio-pci|/var/vms|ariaos-vfio' build_files scripts/build versions tests; then
  echo "Retired VM inference path still referenced." >&2
  exit 1
fi
if ! rg -q 'rm -f /usr/bin/llama-vm' Containerfile; then
  echo "Containerfile must remove the retired llama-vm binary." >&2
  exit 1
fi

readonly blacklist=build_files/etc/modprobe.d/blacklist-nvidia.conf
for module in nvidia_drm nvidia_modeset nouveau; do
  if ! grep -Fqx "install $module /bin/false" "$blacklist"; then
    echo "Invalid permanent display-off policy for module: $module" >&2
    exit 1
  fi
done
for module in nvidia nvidia_uvm; do
  if grep -Fqx "install $module /bin/false" "$blacklist"; then
    echo "Compute module $module must stay on-demand, not hard-blocked." >&2
    exit 1
  fi
done

readonly blacklist_kargs=build_files/usr/lib/bootc/kargs.d/ariaos-blacklist.toml
if ! grep -Fq 'nvidia-drm.modeset=0' "$blacklist_kargs"; then
  echo "Missing nvidia-drm.modeset=0 karg in $blacklist_kargs." >&2
  exit 1
fi
if grep -Fq 'vfio-pci.ids' "$blacklist_kargs"; then
  echo "VFIO kargs must not survive: vfio-pci.ids found." >&2
  exit 1
fi

for required in \
  build_files/usr/libexec/ariaos-egpu \
  build_files/usr/lib/systemd/system/ariaos-egpu.service \
  build_files/usr/share/polkit-1/rules.d/50-ariaos-egpu.rules \
  build_files/etc/yum.repos.d/nvidia-container-toolkit.repo \
  build_files/etc/yum.repos.d/cuda-fedora.repo \
  build_files/etc/dracut.conf.d/ariaos-nvidia.conf; do
  if [[ ! -e $required ]]; then
    echo "Required AriaOS GPU path missing: $required" >&2
    exit 1
  fi
done

if [[ -e build_files/usr/lib/udev/rules.d/69-ariaos-vfio.rules ]]; then
  echo "Retired VFIO udev rule still present." >&2
  exit 1
fi

if ! grep -Fq 'virtqemud.socket' scripts/build/configure-services.sh; then
  echo "Missing virtqemud.socket enablement in configure-services.sh." >&2
  exit 1
fi

if grep -Eq '^v /var/vms ' build_files/usr/lib/tmpfiles.d/ariaos-subvols.conf; then
  echo "/var/vms subvolume declaration must be removed." >&2
  exit 1
fi

echo "Image contract policy passed."
