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
    ln -s "$fixture" "$ARIAOS_TEST_STATE/bin/$command"
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
  )

  if [[ ${ARIAOS_TEST_DIRECT_ROOT:-0} == 1 ]]; then
    (( EUID == 0 )) || fail "direct-root mode requires root privileges"
    "${test_environment[@]}" "$@"
    return
  fi

  unshare -Ur "${test_environment[@]}" "$@"
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
: > "$ARIAOS_TEST_MOUNT/ariaos_home.btrfs.zst"
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

vfio_drivers() {
  mkdir -p "$ARIAOS_TEST_STATE/sys/bus/pci/drivers/vfio-pci" \
    "$ARIAOS_TEST_STATE/sys/bus/pci/drivers/snd_hda_intel"
}

new_environment llama_vm_on
export ARIAOS_TEST_SCENARIO=llama_vm_start
mkdir -p "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.0" \
  "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.1"
vfio_drivers
ln -s ../../drivers/vfio-pci "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.0/driver"
ln -s ../../drivers/vfio-pci "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.1/driver"
: > "$ARIAOS_TEST_STATE/llama.qcow2"
mkdir -p "$ARIAOS_TEST_STATE/models"
mock_commands lspci virsh curl sleep
run_as_mock_root env \
  LLAMA_VM_SYSFS="$ARIAOS_TEST_STATE/sys" \
  LLAMA_VM_DISK="$ARIAOS_TEST_STATE/llama.qcow2" \
  LLAMA_VM_MODELS="$ARIAOS_TEST_STATE/models" \
  bash "$repo_root/build_files/usr/bin/llama-vm" on
for token in \
  "lspci -D -n -d 10de:2504" \
  "lspci -D -n -d 10de:228e" \
  "virsh -c qemu:///system define /tmp/llama-vm" \
  "virsh -c qemu:///system start llama-vm" \
  "curl -fsS http://127.0.0.1:8080/v1/models"; do
  grep -qF "$token" "$ARIAOS_TEST_LOG" || \
    fail "llama-vm on omitted: $token"
done
grep -qF "virsh -c qemu:///system undefine --managed-save llama-vm" "$ARIAOS_TEST_LOG" || \
  fail "llama-vm on did not redefine the domain"

new_environment llama_vm_on_unbound
export ARIAOS_TEST_SCENARIO=llama_vm_start
mkdir -p "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.0" \
  "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.1"
: > "$ARIAOS_TEST_STATE/llama.qcow2"
mkdir -p "$ARIAOS_TEST_STATE/models"
vfio_drivers
ln -s ../../drivers/vfio-pci "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.0/driver"
ln -s ../../drivers/snd_hda_intel "$ARIAOS_TEST_STATE/sys/bus/pci/devices/0000:06:00.1/driver"
mock_commands lspci virsh curl
if run_as_mock_root env \
  LLAMA_VM_SYSFS="$ARIAOS_TEST_STATE/sys" \
  LLAMA_VM_DISK="$ARIAOS_TEST_STATE/llama.qcow2" \
  LLAMA_VM_MODELS="$ARIAOS_TEST_STATE/models" \
  bash "$repo_root/build_files/usr/bin/llama-vm" on; then
  fail "llama-vm on succeeded with audio function not in vfio-pci"
fi
grep -qF "virsh -c qemu:///system start llama-vm" "$ARIAOS_TEST_LOG" && \
  fail "llama-vm on started the VM despite vfio misbinding"

new_environment llama_vm_off
unset ARIAOS_TEST_SCENARIO
mock_commands virsh sleep
run_as_mock_root bash "$repo_root/build_files/usr/bin/llama-vm" off
grep -qF "virsh -c qemu:///system shutdown llama-vm" "$ARIAOS_TEST_LOG" || \
  fail "llama-vm off did not shut down the VM"

echo "Operational tests passed."
