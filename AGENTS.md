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
| `guest/` | VM AI (llama-vm): Containerfile appliance, versioni/checksum, build/install/fetch |
| `scripts/validate/` | Static checks and reusable image contract |
| `tests/` | Isolated, non-destructive operational tests |

Build helpers must not remain in the final image. Keep separate cache boundaries for package installation, service configuration, VFIO reservation, and external tools. Update versions and checksums together. The host image must stay free of model engines and llama.cpp.

Every structural or behavioral change must update both this contract and `README.md` when it affects users.

## 3. Hardware invariants

### Intel Arc

- Intel Arc Lunar Lake is the primary GPU.
- Keep `intel-compute-runtime` and `intel-level-zero` in the base image.
- OpenCL/Level Zero readiness does not authorize adding a model engine, model storage, chatbot, or local-model service.

### NVIDIA eGPU (VM-only, via VFIO)

- NVIDIA is never initialized by the host. The base image is the non-NVIDIA Silverblue; no `nvidia-driver`, `akmod-nvidia`, or Nouveau may exist in the host image.
- The base image must keep explicit `install <module> /bin/false` rules in `/etc/modprobe.d/blacklist-nvidia.conf` for `nvidia`, `nvidia_uvm`, `nouveau`, `nvidia_modeset`, and `nvidia_drm` as belt-and-suspenders. Do not replace them with `alias <module> off`.
- Reserve the eGPU for passthrough by PCI vendor:device, never by BDF: `ariaos-vfio.toml` must keep `vfio-pci.ids=10de:2504,10de:228e` so the reservation is independent of the Thunderbolt port.
- Keep `intel_iommu=on`, `iommu=pt`, and `pcie_acs_override=downstream` in the same file: the enclosure switch shares the eGPU's IOMMU group and must be isolated for clean passthrough.
- Keep the `69-ariaos-vfio.rules` driver_override so neither the GPU nor its audio function is ever bound to a host driver (notably `snd_hda_intel`).
- The eGPU is consumed exclusively by the `llama-vm` libvirt domain (2 vCPU, 4 GiB, headless, user-mode network with hostfwd only on `127.0.0.1:8080`). `llama-vm` regenerates the domain from the live BDF on every start; switching Thunderbolt ports needs no manual edit.
- Cold-unplug only: stop the VM (`llama-vm off`) before disconnecting. Never unplug while the VM runs.
- The guest is a fixed Fedora appliance, kernel pinned via `excludepkgs=kernel*`, NVIDIA KMOD compiled at image build. Do not route around VM passthrough with host-side NVIDIA or model tooling.
- Do not replace Fedora's kernel with a third-party realtime kernel.

## 4. Resource and storage invariants

- Keep Italian and English locale support. `glibc-all-langpacks` is removed; `glibc-langpack-it` and `langpacks-it` stay installed.
- Keep zRAM at 16 GB using `zstd`. Do not change it without explicit user approval.
- Keep the NMI watchdog disabled and Btrfs root compression at `zstd:1` through bootc kernel arguments.
- Keep `btrfsmaintenance` and the scrub/balance timers enabled.
- `/var/games` is a Btrfs subvolume declared through tmpfiles and writable through the declarative `aria-games` group. Never hardcode a personal user or home path.
- `/var/vms` is a Btrfs subvolume declared through tmpfiles; it holds the LLM disk (`/var/vms/llama/llama.qcow2`) and the host-owned GGUF models (`/var/vms/models`), mounted read-only in the guest via virtiofs.
- Prefer Flatpak or Distrobox for nonessential GUI applications.
- Critical system and recovery utilities must be native RPMs. Pika Backup is the sole approved critical Flatpak exception.

## 5. Security and boot invariants

- Root encryption uses LUKS2 and TPM2 through the Discoverable Partitions Specification; avoid persistent manual `/etc/crypttab` edits.
- Force the `crypt` and `tpm2-tss` dracut modules because image builds have no TPM device.
- Standard TPM enrollment uses PCR 7 and may optionally include PCR 0.
- Do not recommend PCR 8 or 9: bootc kernel and initramfs updates would invalidate those measurements.
- VFIO, NVIDIA lock-out, and TPM modules must be applied before the final initramfs regeneration.

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

### Inference VM (llama-vm)

- The host never runs an inference engine: llama.cpp lives only inside the `llama-vm` guest (appliance built by `guest/build.sh` via bootc-image-builder), pinned by `guest/versions.env`, backed by the Vulkan ICD of the in-guest NVIDIA driver.
- The guest kernel is pinned with `excludepkgs=kernel*` and consumes 2 vCPU / 4 GiB; models live host-side in `/var/vms/models` (readonly via virtiofs) and are fetched with `guest/fetch-model.sh`.
- `llama-vm on|off|status` is the sole interaction point: it verifies vfio-pci binding, regenerates the domain from the current BDF, starts/shuts down the VM, and waits on `127.0.0.1:8080/v1`. Changing the Thunderbolt port requires only `off` -> replug -> `on`.
- Any storage-layout or guest-kernel change must update `guest/versions.env`, the guest Containerfile, and the operational tests together.

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
- policy scans for personal paths, retired model components in the host image, legacy build mutations, and VFIO/NVIDIA lock-out rules;
- isolated operational tests for backup cleanup, restore rejection and rollback, DAW profile restoration, and llama-vm on/off sequencing;
- `git diff --check`.

After changes to `Containerfile`, `build_files/`, `scripts/build/`, or external versions, `./scripts/preflight.sh` must also pass. It performs the full Podman build and runs `scripts/validate/image.sh`, which verifies:

- custom FreeRDP packages;
- Intel compute and Kubernetes tools;
- completion files;
- required enabled and masked units;
- sudoers modes;
- sysusers/tmpfiles consistency;
- NVIDIA absence and VFIO lock-out policy;
- absence of retired local-model and build-only paths.

GitHub Actions must run the same image contract after its Buildah build.

## 9. Maintenance skills

- Use `ariaos-optimizer` for periodic efficiency reviews.
- Use `ariaos-posture-check` when available to audit repository alignment.
- Use the repository preflight skill for all image-affecting work.
