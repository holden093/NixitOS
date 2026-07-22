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
  unshare -Ur env PATH="$ARIAOS_TEST_STATE/bin:/usr/bin:/bin" \
    ARIAOS_TEST_LOG="$ARIAOS_TEST_LOG" \
    ARIAOS_TEST_STATE="$ARIAOS_TEST_STATE" \
    ARIAOS_TEST_MOUNT="$ARIAOS_TEST_MOUNT" \
    ARIAOS_TEST_SCENARIO="${ARIAOS_TEST_SCENARIO:-}" \
    "$@"
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

new_environment egpu_up
mock_commands lspci modprobe nvidia-modprobe nvidia-smi udevadm chmod sleep
run_as_mock_root bash "$repo_root/build_files/usr/bin/egpu-up.sh"
for module in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
  grep -q "^modprobe --ignore-install $module$" "$ARIAOS_TEST_LOG" || \
    fail "eGPU activation omitted $module"
done

new_environment egpu_down
mock_commands ls modprobe lsmod sleep
run_as_mock_root bash "$repo_root/build_files/usr/bin/egpu-down.sh"
for module in nvidia_uvm nvidia_drm nvidia_modeset nvidia; do
  grep -q "^modprobe -r $module$" "$ARIAOS_TEST_LOG" || \
    fail "eGPU shutdown omitted $module"
done

echo "Operational tests passed."
