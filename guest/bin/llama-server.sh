#!/usr/bin/env bash
set -Eeuo pipefail

# Wrapper per il server llama.cpp della guest: carica il primo modello GGUF
# montato (readonly via virtiofs da /var/vms/models) e serve l'endpoint
# OpenAI-compatible. L'host raggiunge il servizio solo tramite il forward
# 127.0.0.1:8080 della rete user-mode: il bind su 0.0.0.0 resta interno.
#
# Note: le release ufficiali Linux di llama.cpp non hanno binari CUDA; qui il
# backend Vulkan usa l'ICD Vulkan del driver NVIDIA. Per massimizzare il
# vano sul die GPU il numero di layer e' lasciato alto.

model=$(ls /models/*.gguf 2>/dev/null | head -n1)
if [[ -z ${model} ]]; then
  echo "Nessun modello in /models. Aggiungilo sull'host con guest/fetch-model.sh." >&2
  exit 7
fi

exec /usr/bin/llama-server \
  --host 0.0.0.0 \
  --port 8080 \
  --model "${model}" \
  --n-gpu-layers 999 \
  --ctx-size 4096 \
  --threads 2
