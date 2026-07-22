# AriaOS Agent Contract

This file defines the non-negotiable engineering rules for changes to AriaOS. User-facing operation and installation belong in `README.md`; do not duplicate that material here.

## 1. System model

- AriaOS is a Fedora Silverblue 44 derivative built with `bootc` and `blue-build` for one specific machine.
- The deployed OS is immutable. Persistent system changes must be represented in this repository.
- Use `dnf5` during container builds. Do not use build-time `rpm-ostree install`, `override`, or `cleanup` commands.
- Never recommend live `dnf` or `rpm-ostree install` as a persistent solution. Temporary diagnostics must be identified explicitly as temporary.
- The repository is GPL-3.0; `LICENSE` is authoritative.

## 2. Ownership boundaries

| Location | Responsibility |
|---|---|
| `Containerfile` | Visible stage and cache orchestration |
| `build_files/` | Desired final filesystem state |
| `scripts/build/` | Focused build-time mutations mounted from `build-tools` |
| `versions/external-tools.env` | Pinned upstream versions and SHA-256 digests |
| `scripts/validate/` | Static checks and reusable image contract |
| `tests/` | Isolated, non-destructive operational tests |

Build helpers must not remain in the final image. Keep separate cache boundaries for package installation, service configuration, NVIDIA policy, and external tools. Update versions and checksums together.

Every structural or behavioral change must update both this contract and `README.md` when it affects users.

## 3. Hardware invariants

### Intel Arc

- Intel Arc Lunar Lake is the primary GPU.
- Keep `intel-compute-runtime` and `intel-level-zero` in the base image.
- OpenCL/Level Zero readiness does not authorize adding a model engine, model storage, chatbot, or local-model service.

### NVIDIA eGPU

- NVIDIA is on-demand only.
- The following modules must have exact `install <module> /bin/false` rules in `/etc/modprobe.d/blacklist-nvidia.conf`:
  - `nvidia`
  - `nvidia_uvm`
  - `nouveau`
  - `nvidia_modeset`
  - `nvidia_drm`
- Do not replace these rules with `alias <module> off`; explicit `modprobe --ignore-install` activation depends on the current design.
- `egpu-up.sh` must load `nvidia`, `nvidia_modeset`, `nvidia_uvm`, and `nvidia_drm`, then permit compute and Wayland access to the device nodes.
- Treat the eGPU as cold-unplug only after activation. The user must log out or reboot before unloading or disconnecting it if the display server acquired the device.
- Do not replace Fedora's kernel with a third-party realtime kernel; precompiled NVIDIA compatibility is required.

## 4. Resource and storage invariants

- Keep Italian and English locale support. `glibc-all-langpacks` is removed; `glibc-langpack-it` and `langpacks-it` stay installed.
- Keep zRAM at 16 GB using `zstd`. Do not change it without explicit user approval.
- Keep the NMI watchdog disabled and Btrfs root compression at `zstd:1` through bootc kernel arguments.
- Keep `btrfsmaintenance` and the scrub/balance timers enabled.
- `/var/games` is a Btrfs subvolume declared through tmpfiles and writable through the declarative `aria-games` group. Never hardcode a personal user or home path.
- Prefer Flatpak or Distrobox for nonessential GUI applications.
- Critical system and recovery utilities must be native RPMs. Pika Backup is the sole approved critical Flatpak exception.

## 5. Security and boot invariants

- Root encryption uses LUKS2 and TPM2 through the Discoverable Partitions Specification; avoid persistent manual `/etc/crypttab` edits.
- Force the `crypt` and `tpm2-tss` dracut modules because image builds have no TPM device.
- Standard TPM enrollment uses PCR 7 and may optionally include PCR 0.
- Do not recommend PCR 8 or 9: bootc kernel and initramfs updates would invalidate those measurements.
- NVIDIA policy and TPM modules must be applied before the final initramfs regeneration.

## 6. Operational components

### Backup and restore

- Pika Backup provides daily incremental backups.
- `backup` and `restore` provide bare-metal `/var/home` recovery through Btrfs send/receive streams compressed with zstd.
- Preserve interruption cleanup, partial-file removal, stream validation, previous-home retention, and activation rollback.
- Any storage-layout or subvolume-name change must update both scripts and their operational tests.

### Audio

- Avoid permanent `threadirqs`, `preempt=full`, or equivalent boot tuning.
- `ariaos-daw-launcher` must activate `latency-performance` only for the child process and restore the previously active profile on every exit path.
- Passwordless tuned profile switching is limited to the `audio` group. Realtime operation also requires the `realtime` group.

### Kubernetes

- The base image contains Fedora's `kubernetes1.36-client`, Helm, Bash completion, Minikube, `kubectx`, and `kubens`.
- Minikube and kubectx/kubens use pinned, checksummed upstream artifacts.
- Generate system-wide Bash completion for kubectl and Minikube.
- Use rootless Podman for Minikube. Do not add Docker or an always-on Kubernetes service solely for local development.

## 7. Empirical workflow

1. Inspect the repository and, when relevant, the real system state before proposing a change.
2. Use read-only evidence such as `lsmod`, `systemctl`, `lsblk`, package queries, or supported dry-run modes. Do not assume conventional Fedora state applies unchanged.
3. Implement persistent changes declaratively.
4. Run the smallest relevant checks during development.
5. After any image-affecting change, run the complete preflight and do not publish without a pass.

If a build or command waits for an approval prompt and times out, stop. Do not infer success or bypass validation.

## 8. Required validation

`./scripts/validate.sh` must pass. It covers:

- Bash syntax and ShellCheck when available;
- sudoers parsing;
- policy scans for personal paths, retired model components, legacy build mutations, and NVIDIA rules;
- isolated operational tests for backup cleanup, restore rejection and rollback, DAW profile restoration, and eGPU sequencing;
- `git diff --check`.

After changes to `Containerfile`, `build_files/`, `scripts/build/`, or external versions, `./scripts/preflight.sh` must also pass. It performs the full Podman build and runs `scripts/validate/image.sh`, which verifies:

- custom FreeRDP packages;
- Intel compute and Kubernetes tools;
- completion files;
- required enabled and masked units;
- sudoers modes;
- sysusers/tmpfiles consistency;
- NVIDIA module policy;
- absence of retired local-model and build-only paths.

GitHub Actions must run the same image contract after its Buildah build.

## 9. Maintenance skills

- Use `ariaos-optimizer` for periodic efficiency reviews.
- Use `ariaos-posture-check` when available to audit repository alignment.
- Use the repository preflight skill for all image-affecting work.
