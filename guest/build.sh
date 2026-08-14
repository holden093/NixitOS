#!/usr/bin/env bash
set -Eeuo pipefail

# Costruisce l'immagine disco della guest llama-vm (qcow2 bootabile) a partire
# dal Containerfile in quest'ultima dir, usando bootc-image-builder.
# Operazione pesante: va eseguita una sola volta sulla macchina target, con
# sudo, dopo l'installazione dell'immagine AriaOS aggiornata.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
guest_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly repo_root guest_dir

versions_file="$guest_dir/versions.env"
# shellcheck source=/dev/null
source "$versions_file"

out_dir=/var/vms/llama

die() {
  echo "❌ $*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "Eseguire con sudo (scrive in /var/vms e nello storage rootless di root)."
command -v podman >/dev/null || die "podman non trovato."

echo "==> Pull immagini pinnate..."
podman pull "${FEDORA_BOOTC_IMAGE}@${FEDORA_BOOTC_DIGEST}"
podman pull "${BOOTC_BUILDER_IMAGE}@${BOOTC_BUILDER_DIGEST}"

echo "==> Build dell'immagine guest (Containerfile)..."
podman build \
  --build-arg "BASE_IMAGE=${FEDORA_BOOTC_IMAGE}@${FEDORA_BOOTC_DIGEST}" \
  --build-arg "LLAMA_VERSION=${LLAMA_VERSION}" \
  --build-arg "LLAMA_SRC_SHA256=${LLAMA_SRC_SHA256}" \
  -t localhost/llama-guest:latest \
  "$guest_dir"

mkdir -p "$out_dir/output" "$out_dir/cache"

echo "==> Generazione disco qcow2 con bootc-image-builder..."
podman run --rm \
  --security-opt label=type:unconfined_t \
  -v "$out_dir/cache:/cache" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "$out_dir/output:/output" \
  "${BOOTC_BUILDER_IMAGE}@${BOOTC_BUILDER_DIGEST}" \
  --type qcow2 --local localhost/llama-guest:latest

echo "==> Installazione del disco in ${out_dir}/llama.qcow2..."
qcow2=$(find "$out_dir/output" -maxdepth 1 -name '*.qcow2' | head -n1)
[[ -n $qcow2 ]] || die "bootc-image-builder non ha prodotto un qcow2."
mv -f "$qcow2" "$out_dir/llama.qcow2"
rm -rf "$out_dir/output"

echo "✅ Disco pronto: ${out_dir}/llama.qcow2"
echo "   Prossimo passo: sudo guest/install-vm.sh"
