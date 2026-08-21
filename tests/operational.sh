#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly repo_root
readonly fixture="$repo_root/tests/fixtures/mock-command"
test_root=$(mktemp -d /tmp/ariaos-operational.XXXXXX)

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  echo "Operational test failed: $*" >&2
  exit 1
}

new_environment() {
  local name=$1
  export ARIAOS_TEST_STATE="$test_root/$name"
  export ARIAOS_TEST_LOG="$ARIAOS_TEST_STATE/commands.log"
  export ARIAOS_TEST_MOUNT="$ARIAOS_TEST_STATE/mount"
  mkdir -p "$ARIAOS_TEST_STATE/bin" "$ARIAOS_TEST_MOUNT"
  : > "$ARIAOS_TEST_LOG"
}

mock_commands() {
  local command
  for command in "$@"; do
    # Copia, non symlink: i comandi devono restare leggibili anche quando la
    # suite scende a un utente non privilegiato (il fixture vive nel repo).
    cp "$fixture" "$ARIAOS_TEST_STATE/bin/$command"
  done
}

run_as_mock_root() {
  local -a test_environment=(
    env
    "PATH=$ARIAOS_TEST_STATE/bin:/usr/bin:/bin"
    "ARIAOS_TEST_LOG=$ARIAOS_TEST_LOG"
    "ARIAOS_TEST_STATE=$ARIAOS_TEST_STATE"
    "ARIAOS_TEST_MOUNT=$ARIAOS_TEST_MOUNT"
    "ARIAOS_TEST_SCENARIO=${ARIAOS_TEST_SCENARIO:-}"
    "ARIAOS_TEST_LSOF_PIDS=${ARIAOS_TEST_LSOF_PIDS:-}"
  )

  if [[ ${ARIAOS_TEST_DIRECT_ROOT:-0} == 1 ]]; then
    (( EUID == 0 )) || fail "direct-root mode requires root privileges"
    "${test_environment[@]}" "$@"
    return
  fi

  unshare -Ur "${test_environment[@]}" "$@"
}

run_as_ariaos_user() {
  # ariaos rifiuta di girare come root; quando la suite e' lanciata da root
  # (CI), scende a un utente non privilegiato. La radice dei test (mktemp
  # 0700) e i file diventano leggibili dal mock dei comandi.
  if (( EUID == 0 )); then
    chmod -R a+rwX "$test_root"
    setpriv --reuid=65534 --regid=65534 --clear-groups "$@"
  else
    "$@"
  fi
}

egpu_env_args() {
  egpu_env_vars=(
    "ARIAOS_EGPU_SYSFS=$ARIAOS_TEST_STATE/sys"
    "ARIAOS_EGPU_CDI_DIR=$ARIAOS_TEST_STATE/cdi"
    "ARIAOS_EGPU_DEV_GLOB=$ARIAOS_TEST_STATE/dev/nvidia*"
    "ARIAOS_EGPU_KILL=$ARIAOS_TEST_STATE/bin/kill"
  )
}

egpu_devices() {
  mkdir -p "$ARIAOS_TEST_STATE/dev" "$ARIAOS_TEST_STATE/cdi" \
    "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.0" \
    "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.1"
  : > "$ARIAOS_TEST_STATE/dev/nvidia0"
}

new_environment backup_failure
mock_commands btrfs dialog zstd pv lsblk mount mountpoint umount du clear
if run_as_mock_root bash "$repo_root/build_files/usr/bin/backup"; then
  fail "backup unexpectedly succeeded after compressor failure"
fi
if compgen -G "$ARIAOS_TEST_MOUNT/*.partial.*" >/dev/null; then
  fail "backup left a partial stream behind"
fi
grep -q '^btrfs subvolume delete /var/home-backup$' "$ARIAOS_TEST_LOG" || \
  fail "backup did not remove its temporary snapshot"

new_environment restore_invalid
export ARIAOS_TEST_SCENARIO=restore_invalid
printf 'invalid stream\n' > "$ARIAOS_TEST_MOUNT/ariaos_home.btrfs.zst"
mock_commands btrfs dialog zstdcat pv lsblk mount mountpoint umount stat clear
if run_as_mock_root bash "$repo_root/build_files/usr/bin/restore"; then
  fail "restore unexpectedly accepted an invalid stream"
fi
grep -q '^btrfs subvolume delete /var/home-restored$' "$ARIAOS_TEST_LOG" || \
  fail "restore did not clean its inactive restored subvolume"

new_environment restore_rollback
export ARIAOS_TEST_SCENARIO=restore_rollback
printf 'valid stream\n' > "$ARIAOS_TEST_MOUNT/ariaos_home.btrfs.zst"
mock_commands btrfs dialog zstdcat pv lsblk mount mountpoint umount stat clear mv date
if run_as_mock_root bash "$repo_root/build_files/usr/bin/restore"; then
  fail "restore unexpectedly succeeded after activation failure"
fi
grep -q '^mv /var/home.old_1700000000 /var/home$' "$ARIAOS_TEST_LOG" || \
  fail "restore did not attempt to roll back the original home"

new_environment daw_restore
unset ARIAOS_TEST_SCENARIO
mock_commands tuned-adm sudo
run_as_mock_root env \
  ARIAOS_TUNED_ADM="$ARIAOS_TEST_STATE/bin/tuned-adm" \
  ARIAOS_SUDO="$ARIAOS_TEST_STATE/bin/sudo" \
  bash "$repo_root/build_files/usr/bin/ariaos-daw-launcher" /bin/true
grep -q 'tuned-adm profile latency-performance' "$ARIAOS_TEST_LOG" || \
  fail "DAW launcher did not activate latency-performance"
grep -q 'tuned-adm profile balanced-battery' "$ARIAOS_TEST_LOG" || \
  fail "DAW launcher did not restore the original profile"

new_environment egpu_up
: > "$ARIAOS_TEST_STATE/modules"
egpu_devices
mock_commands lspci modprobe lsmod nvidia-modprobe nvidia-ctk nvidia-smi lsof
egpu_env_args
run_as_mock_root env "${egpu_env_vars[@]}" bash "$repo_root/build_files/usr/libexec/ariaos-egpu" up
grep -qF 'modprobe nvidia' "$ARIAOS_TEST_LOG" || \
  fail "ariaos-egpu up did not load nvidia"
grep -qF 'modprobe nvidia_uvm' "$ARIAOS_TEST_LOG" || \
  fail "ariaos-egpu up did not load nvidia_uvm"
if grep -qE 'modprobe nvidia_drm|modprobe nvidia_modeset' "$ARIAOS_TEST_LOG"; then
  fail "ariaos-egpu up touched the display path"
fi
grep -qF 'nvidia-ctk cdi generate' "$ARIAOS_TEST_LOG" || \
  fail "ariaos-egpu up did not generate the CDI spec"
grep -qx nvidia "$ARIAOS_TEST_STATE/modules" || \
  fail "nvidia not loaded after ariaos-egpu up"
grep -qx nvidia_uvm "$ARIAOS_TEST_STATE/modules" || \
  fail "nvidia_uvm not loaded after ariaos-egpu up"

new_environment egpu_down
printf 'nvidia\nnvidia_uvm\n' > "$ARIAOS_TEST_STATE/modules"
export ARIAOS_TEST_LSOF_PIDS=12345
egpu_devices
: > "$ARIAOS_TEST_STATE/cdi/nvidia.yaml"
mock_commands lspci modprobe lsmod lsof kill sleep
egpu_env_args
run_as_mock_root env "${egpu_env_vars[@]}" bash "$repo_root/build_files/usr/libexec/ariaos-egpu" down
grep -qF 'kill -15 12345' "$ARIAOS_TEST_LOG" || \
  fail "ariaos-egpu down did not terminate the client"
kill_line=$(grep -nF 'kill -15 12345' "$ARIAOS_TEST_LOG" | cut -d: -f1)
mod_line=$(grep -nE 'modprobe -r nvidia$' "$ARIAOS_TEST_LOG" | cut -d: -f1)
[[ -n $kill_line && -n $mod_line && $kill_line -lt $mod_line ]] || \
  fail "ariaos-egpu down killed the client after unloading modules"
[[ ! -e "$ARIAOS_TEST_STATE/cdi/nvidia.yaml" ]] || \
  fail "ariaos-egpu down left the CDI spec behind"
grep -qx 1 "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.0/remove" || \
  fail "ariaos-egpu down did not remove the GPU from the bus"
grep -qx 1 "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.1/remove" || \
  fail "ariaos-egpu down did not remove the audio function from the bus"

new_environment egpu_down_no_unload
export ARIAOS_TEST_SCENARIO=egpu_no_unload
printf 'nvidia\nnvidia_uvm\n' > "$ARIAOS_TEST_STATE/modules"
egpu_devices
mock_commands lspci modprobe lsmod lsof kill sleep
egpu_env_args
if run_as_mock_root env "${egpu_env_vars[@]}" bash "$repo_root/build_files/usr/libexec/ariaos-egpu" down; then
  fail "ariaos-egpu down succeeded with a module still loaded"
fi
[[ ! -e "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.0/remove" ]] || \
  fail "ariaos-egpu down removed the device despite a busy module"

echo "Operational tests passed."
