#!/usr/bin/env bash
set -Eeuo pipefail

if rg -n 'rpm-ostree (install|override|cleanup)' Containerfile scripts/build; then
  echo "Legacy rpm-ostree mutation found in the container build; use dnf5." >&2
  exit 1
fi

for helper in \
  install-packages.sh \
  install-kubernetes-tools.sh \
  configure-services.sh; do
  if ! rg -q "scripts/build/$helper" Containerfile; then
    echo "Containerfile does not invoke required build module: $helper" >&2
    exit 1
  fi
done
