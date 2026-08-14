# AriaOS Best Practices

## Fedora Silverblue & bootc
- **Minimalism**: Only include packages in the base image that are essential for the system to boot and provide core functionality. Use Flatpaks or Distroboxes for user applications.
- **GitOps Flow**: Every change should be reflected in the `Containerfile`. Avoid manual `rpm-ostree install` on the running system except for testing.
- **Clean Layers**: Use `dnf5` during bootc container builds and run `dnf5 clean all` after installs to keep image size down.

## eGPU Management (NVIDIA via VFIO)
- **Reservation**: The eGPU must stay bound to `vfio-pci` (`vfio-pci.ids=`, `pcie_acs_override=downstream`); the host must never bind a NVIDIA/Nouveau/audio driver.
- **VM-only**: The device belongs to the `llama-vm` domain. `powertop` can confirm the host does not initialize the NVIDIA functions at all.
- **Cold-unplug**: Always `llama-vm off` before disconnecting the Thunderbolt cable.

## Intel Arc (Media and Compute)
- **Media Runtime**: Ensure `libva-intel-media-driver` is correctly configured for hardware acceleration in apps like OBS or FFmpeg.
- **Compute Runtime**: Keep `intel-compute-runtime` and `intel-level-zero` available as the generic OpenCL/Level Zero foundation; model engines remain separate components.

## Build Optimization
- **Mount Cache**: Use `--mount=type=cache,dst=/var/cache` in `Containerfile` to speed up builds by caching RPM metadata and packages.
- **Bootc Lint**: Always run `bootc container lint` at the end of the build.
