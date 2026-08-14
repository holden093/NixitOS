---
name: ariaos-optimizer
description: Specialized for optimizing AriaOS (a Fedora-based bootc image). It compares the codebase (Containerfile, build_files) with the current running environment to identify performance bottlenecks, redundant packages, and better configuration patterns. Use it to improve system efficiency and maintainability.
---

# AriaOS Optimizer

This skill helps you refine the AriaOS codebase by comparing it with the active operating system and applying efficiency best practices for Fedora Silverblue/bootc images.

## Core Workflows

### 1. Codebase vs. Environment Analysis
- Compare the list of packages in `Containerfile` with the output of `rpm-ostree status` and `rpm -qa`.
- Identify "ghost" packages that are installed but never used or have more efficient alternatives.
- Check active services (`systemctl list-units --type=service --state=running`) and cross-reference with the codebase to see if they are necessary or can be optimized.

### 2. Layer & Build Optimization
- Group build-time `dnf5 install` commands to reduce image layers.
- Use multi-stage builds if necessary for temporary build tools.
- Ensure `dnf5 clean all` is used after every major install step.

### 3. Performance Tuning
- Suggest `sysctl` tweaks based on hardware (e.g., VM workload, SSD optimization).
- Review `blacklist-nvidia.conf`, the boot kargs (`ariaos-blacklist.toml`), and `configure-nvidia-policy.sh` to confirm the eGPU stays compute-only and on-demand, never on the display path.
- Check the on-demand eGPU footprint (`ariaos llm nvidia up/down`, module load/unload, CDI spec) instead of driver loading speed.

### 4. Hardware-Specific Refinements
- Use `lshw`, `lspci`, and `lsusb` to detect hardware and suggest missing drivers or firmware in the `Containerfile`.
- Validate Intel Arc desktop, media, OpenCL, and Level Zero support without assuming a particular model engine.

## Best Practices
- Refer to `references/best-practices.md` for detailed guidance on `blue-build` and `bootc`.
- Use `scripts/check_efficiency.sh` to gather a performance baseline before making changes.
