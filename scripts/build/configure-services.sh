#!/usr/bin/env bash
set -Eeuo pipefail

readonly enabled_units=(
  podman.socket
  virtqemud.socket
  tuned.service
  btrfs-scrub.timer
  btrfs-balance.timer
  ariaos-swapfile.service
  var-swapfile.swap
)

systemctl enable "${enabled_units[@]}"
systemctl mask ModemManager.service
