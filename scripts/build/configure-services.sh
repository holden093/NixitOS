#!/usr/bin/env bash
set -Eeuo pipefail

readonly enabled_units=(
  podman.socket
  tuned.service
  btrfs-scrub.timer
  btrfs-balance.timer
)

systemctl enable "${enabled_units[@]}"
systemctl mask ModemManager.service
