#!/usr/bin/env bash
set -Eeuo pipefail

# Predispone /var/vms/models e avvia la VM llama-vm (definisce il dominio con i
# BDF correnti della eGPU, la avvia e attende l'endpoint OpenAI).
# Richiede l'immagine AriaOS aggiornata (per /usr/bin/llama-vm) e il disco
# guest generato da build.sh. Il modello GGUF va aggiunto con fetch-model.sh.

die() {
  echo "❌ $*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "Eseguire con sudo."
[[ -x /usr/bin/llama-vm ]] || die "/usr/bin/llama-vm non presente: installare prima l'immagine AriaOS aggiornata."
[[ -f /var/vms/llama/llama.qcow2 ]] || die "Disco guest mancante: eseguire prima guest/build.sh."

install -d -m 0755 /var/vms/models

echo "==> Definizione e avvio della VM (attende l'endpoint)..."
/usr/bin/llama-vm on

echo "✅ VM attiva. Endpoint: http://127.0.0.1:8080/v1"
echo "   Console guest: sudo virsh -c qemu:///system console llama-vm"
