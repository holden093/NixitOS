#!/usr/bin/env bash
set -Eeuo pipefail

readonly image=${1:?Usage: image.sh IMAGE}
readonly runtime=${ARIAOS_CONTAINER_RUNTIME:-podman}

run_image() {
  "$runtime" run --rm "$image" "$@"
}

assert_unit_state() {
  local unit=$1
  local expected=$2
  local actual
  actual=$(run_image systemctl is-enabled "$unit" 2>/dev/null || true)
  if [[ $actual != "$expected" ]]; then
    echo "Unexpected systemd state for $unit: expected $expected, got ${actual:-unknown}" >&2
    exit 1
  fi
}

freerdp_version=$(run_image rpm -q freerdp-libs)
if [[ $freerdp_version != *ariaos* ]]; then
  echo "Unexpected FreeRDP package: $freerdp_version" >&2
  exit 1
fi

for package in intel-compute-runtime intel-level-zero nvidia-container-toolkit \
  gcc-c++ cmake ninja-build vulkan-headers cuda-toolkit; do
  if ! run_image rpm -q "$package" >/dev/null 2>&1; then
    echo "Required compute/container package is missing: $package" >&2
    exit 1
  fi
done
run_image cmake --version >/dev/null
run_image ninja --version >/dev/null
run_image /usr/local/cuda/bin/nvcc --version >/dev/null
run_image test -s /etc/profile.d/cuda.sh

if ! run_image rpm -q nvidia-driver >/dev/null 2>&1; then
  echo "NVIDIA host driver must be present in the image." >&2
  exit 1
fi

run_image kubectl version --client >/dev/null
run_image helm version --short >/dev/null
run_image minikube version --short >/dev/null
run_image kubectx --help >/dev/null
run_image kubens --help >/dev/null

for completion in kubectl minikube; do
  if ! run_image test -s "/etc/bash_completion.d/$completion"; then
    echo "Missing Bash completion: $completion" >&2
    exit 1
  fi
done

for removed_path in \
  /usr/bin/aria \
  /usr/share/aria \
  /usr/share/aria-gguf-engine \
  /usr/lib/sysusers.d/ai-compute.conf \
  /usr/bin/llama-vm \
  /etc/sudoers.d/llama-vm \
  /usr/lib/bootc/kargs.d/ariaos-vfio.toml \
  /usr/lib/udev/rules.d/69-ariaos-vfio.rules \
  /etc/dracut.conf.d/ariaos-vfio.conf \
  /usr/lib/bootc/kargs.d/bluebuild-kargs.toml; do
  if run_image test -e "$removed_path"; then
    echo "Removed path remains in image: $removed_path" >&2
    exit 1
  fi
done

for module in nvidia_drm nvidia_modeset nouveau; do
  run_image grep -Fqx "install $module /bin/false" /etc/modprobe.d/blacklist-nvidia.conf
done
for module in nvidia nvidia_uvm; do
  if run_image grep -Fqx "install $module /bin/false" /etc/modprobe.d/blacklist-nvidia.conf; then
    echo "Compute module $module must stay on-demand, not hard-blocked." >&2
    exit 1
  fi
done

run_image grep -Fq 'nvidia-drm.modeset=0' /usr/lib/bootc/kargs.d/ariaos-blacklist.toml

if ! run_image test -x /usr/libexec/ariaos-egpu; then
  echo "ariaos-egpu helper missing or not executable." >&2
  exit 1
fi
if ! run_image test -x /usr/libexec/ariaos-swapfile; then
  echo "ariaos-swapfile helper missing or not executable." >&2
  exit 1
fi

# Swap su disco: zRAM deve restare disattivato per non sottrarre RAM alle inferenze.
run_image grep -Fqx 'zram-size = 0' /etc/systemd/zram-generator.conf
run_image grep -Fqx 'What=/var/swapfile' /usr/lib/systemd/system/var-swapfile.swap
for path in \
  /usr/lib/systemd/system/ariaos-egpu.service \
  /usr/share/polkit-1/rules.d/50-ariaos-egpu.rules; do
  if ! run_image test -e "$path"; then
    echo "Required AriaOS GPU path missing: $path" >&2
    exit 1
  fi
done

for unit in podman.socket virtqemud.socket tuned.service btrfs-scrub.timer btrfs-balance.timer \
  ariaos-swapfile.service var-swapfile.swap; do
  assert_unit_state "$unit" enabled
done
assert_unit_state ModemManager.service masked
assert_unit_state ariaos-egpu.service disabled
assert_unit_state nvidia-cdi-refresh.service masked
assert_unit_state nvidia-cdi-refresh.path masked

mode=$(run_image stat -c '%a' /etc/sudoers.d/tuned)
if [[ $mode != 440 ]]; then
  echo "Unexpected sudoers mode for tuned: $mode" >&2
  exit 1
fi

run_image grep -Fqx 'g aria-games - -' /usr/lib/sysusers.d/aria-games.conf
run_image grep -Fqx 'v /var/games 2775 root aria-games - -' \
  /usr/lib/tmpfiles.d/ariaos-subvols.conf

for build_path in /ariaos-build /scripts/build /versions/external-tools.env; do
  if run_image test -e "$build_path"; then
    echo "Build-only path remains in final image: $build_path" >&2
    exit 1
  fi
done

echo "Image validation passed."
echo "FreeRDP: $freerdp_version"
