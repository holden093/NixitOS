# syntax=docker/dockerfile:1
FROM scratch AS ctx
COPY build_files /

FROM scratch AS build-tools
COPY scripts/build /scripts/build
COPY versions /versions

# ==========================================
# STAGE: Rebuild FreeRDP with FFmpeg/x264 + VAAPI
# ==========================================
# Isolated from the main image to avoid libavcodec-free / ffmpeg-libs
# conflicts between Fedora and RPM Fusion packages.

FROM fedora:44 AS freerdp-builder
RUN dnf install -y 'dnf-command(builddep)' rpm-build && \
    dnf install -y \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm && \
    dnf install -y ffmpeg-devel && \
    dnf builddep --define '_with_ffmpeg 1' -y freerdp && \
    dnf download --source freerdp && \
    rpmbuild --rebuild \
        --define '_with_ffmpeg 1' \
        --define 'dist .ariaos' \
        freerdp-*.src.rpm && \
    echo "AriaOS: FreeRDP RPMs built with FFmpeg/x264 + VAAPI."

# L'immagine base pulita, senza alcun driver NVIDIA
FROM ghcr.io/blue-build/base-images/fedora-silverblue:44

# ==========================================
# 1. COPIA FILE CUSTOM E PERMESSI
# ==========================================

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    rsync -a /ctx/ / && \
    # Remove components retired from earlier AriaOS images. Deleting them from
    # build_files alone does not remove files inherited by an image upgrade.
    rm -rf /usr/share/aria /usr/share/aria-gguf-engine && \
    rm -f /usr/bin/aria /usr/lib/sysusers.d/ai-compute.conf && \
    chmod +x /usr/bin/llama-vm /usr/bin/backup /usr/bin/restore /usr/bin/ariaos-daw-launcher && \
    chmod 0440 /etc/sudoers.d/llama-vm /etc/sudoers.d/tuned

RUN visudo -cf /etc/sudoers.d/llama-vm && \
    visudo -cf /etc/sudoers.d/tuned

# ==========================================
# 2. MODULI DI BUILD
# ==========================================

RUN --mount=type=bind,from=build-tools,source=/,target=/ariaos-build \
    --mount=type=cache,dst=/var/cache \
    bash /ariaos-build/scripts/build/install-packages.sh

RUN --mount=type=bind,from=build-tools,source=/,target=/ariaos-build \
    bash /ariaos-build/scripts/build/configure-services.sh

RUN --mount=type=bind,from=build-tools,source=/,target=/ariaos-build \
    bash /ariaos-build/scripts/build/install-kubernetes-tools.sh \
        /ariaos-build/versions/external-tools.env

# ==========================================
# 2b. OVERRIDE FREERDP WITH FFMPEG/x264 + VAAPI BUILD
# ==========================================

# Copy all RPMs built in the isolated freerdp-builder stage and
# replace the stock packages.  freerdp-libs and libwinpr are version-
# locked (must match), and both are present in the base image.

COPY --from=freerdp-builder /root/rpmbuild/RPMS/x86_64/ /tmp/freerdp-rpms/
RUN dnf5 install -y --allowerasing --allow-downgrade \
        /tmp/freerdp-rpms/freerdp-libs-[0-9]*.rpm \
        /tmp/freerdp-rpms/libwinpr-[0-9]*.rpm && \
    rm -rf /tmp/freerdp-rpms && \
    dnf5 clean all && \
    echo "AriaOS: FreeRDP replaced with FFmpeg/x264 + VAAPI build."

# ==========================================
# 3. BRANDING & IDENTITÀ
# ==========================================

RUN sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="AriaOS (BlueBuild Edition)"/' /etc/os-release && \
    sed -i 's/^NAME=.*/NAME="AriaOS"/' /etc/os-release && \
    sed -i 's/^ID=fedora/ID=ariaos/' /etc/os-release && \
    sed -i 's/^ID_LIKE=.*/ID_LIKE="fedora"/' /etc/os-release && \
    sed -i 's|^HOME_URL=.*|HOME_URL="https://github.com/holden093/ariaos"|' /etc/os-release

# ==========================================
# 4. PLYMOUTH & INITRAMFS
# ==========================================

RUN cp -n /usr/share/plymouth/themes/spinner/*.png /usr/share/plymouth/themes/ariaos/ && \
    plymouth-set-default-theme ariaos && \
    # Creiamo /var/roothome per evitare che dracut fallisca a causa di /root come symlink rotto nel container
    mkdir -p /var/roothome && \
    # Rigeneriamo l'initramfs ALLA FINE per applicare i driver VFIO, le esclusioni NVIDIA e il TPM
    dracut -f --regenerate-all

# ==========================================
# 5. VERIFICA E LINTING
# ==========================================

RUN bootc container lint
