#!/usr/bin/env bash
set -Eeuo pipefail

readonly rpmfusion_free=https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm
readonly rpmfusion_nonfree=https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm

readonly packages=(
  # Multimedia and Intel Arc compute
  libva-intel-media-driver
  intel-compute-runtime
  intel-level-zero

  # Hardware and eGPU diagnostics
  bolt
  pciutils
  lshw
  lm_sensors
  glx-utils
  vulkan-loader
  vulkan-tools
  clinfo

  # Networking and administration
  wireguard-tools
  nmap
  iperf3
  mtr
  tcpdump
  bind-utils
  tmux
  jq
  dialog
  pv

  # Virtualization and containers
  libvirt
  virt-manager
  qemu-kvm
  podman-compose
  distrobox

  # Development and Kubernetes
  langpacks-it
  nodejs-npm
  git
  gh
  ripgrep
  kubernetes1.36-client
  helm
  bash-completion

  # Desktop and user applications
  yaru-theme
  gnome-tweaks
  gnome-shell-extension-user-theme
  loupe
  evince
  remmina
  steam-devices
  geary
  gedit
  vlc
  rbw
  btop
  powertop
  nvtop
  obs-studio
  obs-studio-plugin-x264
  ckan

  # Backup, storage, and low-latency audio
  borgbackup
  btrfsmaintenance
  realtime-setup
  tuned
  tuned-profiles-realtime
)

readonly removed_packages=(
  gnome-software
  ibus-typing-booster
  ibus-anthy
  ibus-anthy-python
  ibus-hangul
  ibus-libpinyin
  ibus-m17n
  ibus-unikey
  google-noto-sans-cjk-fonts
  cldr-emoji-annotation
  cldr-emoji-annotation-dtd
)

dnf5 install -y "$rpmfusion_free" "$rpmfusion_nonfree"

glibc_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' glibc)
dnf5 swap -y glibc-all-langpacks "glibc-langpack-it-${glibc_version}"
dnf5 remove -y --no-autoremove "${removed_packages[@]}"

# CKAN's Mono post-install expects the conventional certificate paths, whose
# legacy ca-bundle.crt symlink was dropped on Fedora 44.
ln -sf /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt
ln -sf /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/cert.pem
dnf5 install -y "${packages[@]}"
dnf5 clean all
