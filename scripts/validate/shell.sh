#!/usr/bin/env bash
set -Eeuo pipefail

mapfile -t shell_scripts < <(
  find build_files/usr/bin scripts .antigravity/skills guest -type f -print0 |
    xargs -0 grep -Il '^#!.*\(ba\)\?sh'
)

for script in "${shell_scripts[@]}"; do
  bash -n "$script"
done

if command -v shellcheck >/dev/null; then
  shellcheck "${shell_scripts[@]}"
fi

if command -v visudo >/dev/null; then
  for sudoers_file in build_files/etc/sudoers.d/*; do
    visudo -cf "$sudoers_file"
  done
fi
