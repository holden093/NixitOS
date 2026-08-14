#!/usr/bin/env bash
set -Eeuo pipefail

# Scarica un modello GGUF sull'host in /var/vms/models (montato poi readonly
# nella guest). Uso: sudo guest/fetch-model.sh URL [SHA256]

[[ $# -ge 1 ]] || { echo "Uso: fetch-model.sh URL [SHA256]" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Eseguire con sudo." >&2; exit 1; }

url=$1
expected=${2:-}
dest_dir=/var/vms/models
filename=$(basename "$url")
dest="$dest_dir/$filename"

mkdir -p "$dest_dir"

echo "==> Scaricamento ${url}"
curl -fL --progress-bar -o "$dest.part" "$url"

if [[ -n $expected ]]; then
  echo "==> Verifica checksum..."
  echo "$expected  $dest.part" | sha256sum -c -
fi

mv -f "$dest.part" "$dest"
echo "✅ Modello salvato: $dest"
echo "   Ricarica la VM per montarlo: sudo llama-vm off && sudo llama-vm on"
