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

for package in intel-compute-runtime intel-level-zero; do
  if ! run_image rpm -q "$package" >/dev/null 2>&1; then
    echo "Required Intel compute package is missing: $package" >&2
    exit 1
  fi
done

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
  /usr/lib/sysusers.d/ai-compute.conf; do
  if run_image test -e "$removed_path"; then
    echo "Removed local-model path remains in image: $removed_path" >&2
    exit 1
  fi
done

for module in nvidia nvidia_uvm nouveau nvidia_modeset nvidia_drm; do
  run_image grep -Fqx "install $module /bin/false" /etc/modprobe.d/blacklist-nvidia.conf
done

for unit in podman.socket tuned.service btrfs-scrub.timer btrfs-balance.timer; do
  assert_unit_state "$unit" enabled
done
for unit in \
  ModemManager.service \
  nvidia-hibernate.service \
  nvidia-resume.service \
  nvidia-suspend.service \
  nvidia-suspend-then-hibernate.service \
  nvidia-powerd.service \
  nvidia-persistenced.service; do
  assert_unit_state "$unit" masked
done

for sudoers_file in egpu tuned; do
  mode=$(run_image stat -c '%a' "/etc/sudoers.d/$sudoers_file")
  if [[ $mode != 440 ]]; then
    echo "Unexpected sudoers mode for $sudoers_file: $mode" >&2
    exit 1
  fi
done

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
