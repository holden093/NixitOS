---
name: ariaos-preflight
description: Mandatory pre-push validation for AriaOS. Runs a local podman build of the Containerfile and verifies the result before any git push. Use this EVERY time you modify the Containerfile or build_files/ — pushing without a passing local build is forbidden by project convention.
---

# AriaOS Preflight

Enforces the rule: **every change to `Containerfile` or `build_files/` MUST pass a local `podman build` before pushing to GitHub.**

## Why

The CI runner on GitHub has subtle differences from the local environment (package versions, network, caching). A push that fails CI means a broken image at `ghcr.io/holden093/ariaos:latest` and a wasted build cycle. Local validation catches these issues early.

## When to Run

- After ANY edit to `Containerfile`
- After ANY file added/changed under `build_files/`
- Before `git push` (always)

## Quick Check

```bash
# Run from the repo root:
./scripts/preflight.sh
```

This script:
1. Runs `scripts/validate.sh`, including mocked non-destructive operational tests.
2. Reports image-affecting changes.
3. Builds the complete image with Podman.
4. Runs the reusable `scripts/validate/image.sh` image contract, also used by CI.
5. Removes the test image unless `ARIAOS_KEEP_PREFLIGHT_IMAGE=1` is set.

## Pass Criteria

- `podman build` exits 0
- All Containerfile steps complete
- `bootc container lint` shows no new errors
- The built image contains the custom `.ariaos` FreeRDP package.
- Removed local-model packages and paths are absent.
- Required services, masks, sudoers modes, storage declarations, and build-only path cleanup match the image contract.

## When It Fails

1. **Read the build output carefully** — the error is usually in the last 20 lines
2. **Fix the root cause**, not the symptom — a package conflict needs a structural fix, not a workaround
3. **Rebuild and re-test** until it passes
4. **Never bypass** — there is no `--skip-tests` for AriaOS

## Example Workflow

```
$ vim Containerfile
$ ./scripts/preflight.sh
  → Build failed: ffmpeg-libs conflicts with libavcodec-free
$ vim Containerfile   # fix the conflict
$ ./scripts/preflight.sh
  → Build PASSED ✅
$ git push
```

## CI Correlation

The GitHub Actions workflow (`.github/workflows/build-image.yml`) runs the same `Containerfile` via `buildah`. A passing local build is a strong (but not 100%) predictor of CI success. The most common divergence is package version skew — the local build can catch these if you run `podman build --no-cache` periodically.
