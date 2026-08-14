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

Build helpers must not remain in the final image. Keep separate cache boundaries for package installation, service configuration, NVIDIA policy, and external tools. Update versions and checksums together. The host image must stay free of model engines and llama.cpp binaries.

Every structural or behavioral change must update both this contract and `README.md` when it affects users.

## 3. Hardware invariants

### Intel Arc

- Intel Arc Lunar Lake is the primary GPU.
- Keep `intel-compute-runtime` and `intel-level-zero` in the base image.
- OpenCL/Level Zero readiness does not authorize adding a model engine, model storage, chatbot, or local-model service.

### NVIDIA eGPU (compute-only, on-demand)

- The NVIDIA driver exists in the image (base `fedora-silverblue-nvidia`) but is **compute-only**: only the `nvidia` and `nvidia_uvm` modules are loaded, on demand, exclusively by `ariaos-egpu.service`.
- The display path must stay permanently unloadable and unloaded: `/etc/modprobe.d/blacklist-nvidia.conf` keeps hard `install <module> /bin/false` rules for `nvidia_drm`, `nvidia_modeset`, and `nouveau`. Do not replace them with `alias <module> off`. Without `nvidia_drm` there is no DRM node, so GNOME cannot enumerate the eGPU.
- `nvidia` and `nvidia_uvm` must remain **on-demand**: plain `blacklist` (no autoload), never `install /bin/false`, so explicit `modprobe` from the service works.
- The boot kargs keep `nvidia-drm.modeset=0`; `rd.driver.blacklist` and `modprobe.blacklist` cover `nvidia_drm,nvidia_modeset,nouveau` only.
- `ariaos-egpu.service` is the only privileged NVIDIA entry point, gated by a polkit rule for the `wheel` group on that single unit. It loads the compute modules, creates the device nodes, generates the runtime CDI spec in `/run/cdi`, and on stop kills clients, unloads the modules, and removes the PCI devices so the Thunderbolt cable can be unplugged.
- `nvidia-suspend/resume/hibernate`, `nvidia-powerd`, and `nvidia-persistenced` stay masked; the base image's autoload files (`/usr/lib/modprobe.d/nvidia*.conf`, `/usr/lib/bootc/kargs.d/bluebuild-kargs.toml`, NVIDIA udev rules) are removed at build time by `configure-nvidia-policy.sh`, before the final initramfs regeneration.
- Cold-unplug only: run `ariaos llm nvidia down` (which also removes the PCI devices) before disconnecting. Never unplug while the driver is bound.
- Intel Arc is always the desktop GPU: no NVIDIA module may ever bind at boot, and no NVIDIA path may drive the display.
- Do not replace Fedora's kernel with a third-party realtime kernel.

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
- NVIDIA display-off policy and TPM modules must be applied before the final initramfs regeneration.

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

### Inferenza locale (ariaos llm)

- The host never runs an inference engine: llama.cpp lives only in user toolboxes, outside the image. `ariaos llm` orchestrates the two backends and delegates server startup to commands declared in `/usr/lib/ariaos/llm.conf` (overridable in `/etc/ariaos/llm.conf`); no model or engine path may be hardcoded in the image.
- `ariaos llm intel` targets Intel Arc (Vulkan); `ariaos llm nvidia` targets the compute-only eGPU (CUDA). The two backends are mutually exclusive: `up` on one refuses while the other is active, preventing RAM/GPU contention. Ports are fixed and distinct (`INTEL_PORT=8080`, `NVIDIA_PORT=8081`).
- `ariaos llm` must run as the invoking user, never as root. The privileged NVIDIA path belongs exclusively to `ariaos-egpu.service`, authorized passwordless only for the `wheel` group on that unit via polkit.
- `nvidia-container-toolkit` provides CDI support; `ariaos-egpu up` generates the spec in `/run/cdi` from the runtime driver. Any change to the driver/module policy must update `configure-nvidia-policy.sh`, the blacklist/kargs files, and the operational tests together.

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
- policy scans for personal paths, retired model components in the host image, legacy build mutations, and the NVIDIA display-off/on-demand policy;
- isolated operational tests for backup cleanup, restore rejection and rollback, DAW profile restoration, and ariaos-egpu / ariaos llm sequencing;
- `git diff --check`.

After changes to `Containerfile`, `build_files/`, `scripts/build/`, or external versions, `./scripts/preflight.sh` must also pass. It performs the full Podman build and runs `scripts/validate/image.sh`, which verifies:

- custom FreeRDP packages;
- Intel compute and Kubernetes tools;
- completion files;
- required enabled and masked units;
- sudoers modes;
- sysusers/tmpfiles consistency;
- NVIDIA presence and display-off/on-demand policy;
- absence of retired local-model, VFIO/VM, and build-only paths.

GitHub Actions must run the same image contract after its Buildah build.

## 9. Maintenance skills

- Use `ariaos-optimizer` for periodic efficiency reviews.
- Use `ariaos-posture-check` when available to audit repository alignment.
- Use the repository preflight skill for all image-affecting work.
