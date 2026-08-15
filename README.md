# AriaOS

AriaOS è un sistema operativo personale, immutabile e dichiarativo basato su Fedora Silverblue 44, `bootc` e `blue-build`.

> [!WARNING]
> Questa immagine è progettata per uno specifico laptop Intel Lunar Lake con eGPU NVIDIA Thunderbolt. Non è una distribuzione generica e può essere inadatta o pericolosa su hardware diverso.

## Obiettivi

- Sistema riproducibile: ogni modifica persistente vive nel repository.
- Base nativa essenziale, con Flatpak e Distrobox per applicazioni non critiche.
- Intel Arc sempre disponibile per desktop, media e calcolo OpenCL/Level Zero.
- eGPU NVIDIA **compute-only on-demand**: caricata solo per l'inferenza CUDA, mai sul percorso display.
- Backup giornalieri e ripristino bare-metal indipendenti.
- Buona autonomia nell'uso normale e tuning dinamico per sessioni audio.

## Piattaforma

| Area | Configurazione |
|---|---|
| Base | Fedora Silverblue 44, `bootc`, `blue-build` |
| Desktop | GNOME Wayland con tema Yaru |
| GPU primaria | Intel Arc Lunar Lake (display + Vulkan) |
| GPU secondaria | NVIDIA eGPU Thunderbolt, compute-only on-demand (mai display) |
| Inferenza IA | `ariaos llm intel` (Vulkan, porta 8080) / `ariaos llm nvidia` (CUDA, porta 8081) |
| Storage | Btrfs con compressione `zstd:1` |
| Cifratura | LUKS2, TPM 2.0 e Discoverable Partitions Specification |
| Memoria | 32 GB RAM, zRAM da 16 GB con `zstd` |

## Funzionalità principali

### GPU e calcolo

Intel Arc dispone di `intel-compute-runtime`, `intel-level-zero`, OpenCL e strumenti Vulkan per desktop, media e calcolo, senza alcun motore LLM host-side.

La eGPU NVIDIA (RTX 3060 `10de:2504` + audio `10de:228e`) è **compute-only**: a boot non viene mai inizializzata. `ariaos-egpu.service` carica on-demand solo i moduli di calcolo (`nvidia`, `nvidia_uvm`); i moduli display (`nvidia_drm`, `nvidia_modeset`) e `nouveau` sono bloccati in modo permanente. Senza nodo DRM la sessione GNOME non può enumerare la scheda, quindi non esiste alcun rischio che la sessione venga "rubata" o che lo scaricamento fallisca.

> [!CAUTION]
> Scollegamento a freddo: eseguire prima `ariaos llm nvidia down` (che rimuove anche i device dal bus PCIe). Non scollegare mai il cavo Thunderbolt con il driver attivo.

### Inferenza locale (ariaos llm)

`ariaos llm` orchestra due backend di inferenza locale mutuamente esclusivi. L'immagine **non contiene né motori né modelli**: fornisce driver, spec CDI e orchestrazione, mentre llama.cpp vive nei tuoi toolbox e i comandi di avvio dei server sono dichiarati in `/etc/ariaos/llm.conf` (default in `/usr/lib/ariaos/llm.conf`).

#### Comandi

```bash
ariaos llm status              # stato di entrambi i backend e dei driver
ariaos llm intel up|down       # backend Vulkan su Intel Arc (porta 8080)
ariaos llm nvidia up|down      # backend CUDA sulla eGPU (porta 8081)
```

Il comando gira **sempre come utente** e rifiuta esplicitamente l'esecuzione come root: deve poter lanciare processi utente. La parte privilegiata (caricamento/scaricamento del driver NVIDIA) è affidata esclusivamente a `ariaos-egpu.service`.

#### Stati riportati da `status`

Per ogni backend:

| Stato | Significato |
|---|---|
| `non configurato` | `START` vuoto in `llm.conf`: il backend non è ancora dichiarato |
| `fermo` | comando `START` presente, ma l'endpoint di health check non risponde |
| `attivo su porta N` | l'endpoint risponde |

Per il backend `nvidia` viene indicato anche `driver attivo`/`driver fermo`, in base allo stato di `ariaos-egpu.service`.

#### Mutua esclusione e porte

I due backend sono esclusivi: `intel up` rifiuta se il backend NVIDIA è attivo (server raggiungibile o driver caricato), e `nvidia up` rifiuta se il backend Intel risponde. Il vincolo serve a evitare contesa di RAM/GPU, non soltanto di porta. Le porte sono fisse e distinte: `INTEL_PORT=8080`, `NVIDIA_PORT=8081`.

#### Ciclo di vita NVIDIA

`ariaos llm nvidia up` esegue, nell'ordine:

1. `systemctl start ariaos-egpu.service` (via polkit): carica `nvidia` + `nvidia_uvm`, crea i device node, genera la spec CDI in `/run/cdi/nvidia.yaml`;
2. il comando `NVIDIA_START` come utente;
3. attesa dell'endpoint di health check (default 120 s).

`ariaos llm nvidia down` fa il percorso inverso: arresta il server, attende che la porta si liberi, poi `systemctl stop ariaos-egpu.service` che termina i client residui, scarica i moduli e rimuove i device dal bus PCIe.

#### Privilegi e polkit

L'autorizzazione passwordless per `ariaos-egpu.service` vale solo per il gruppo `wheel` e per **sessioni locali attive**. Via SSH la regola non scatta: `ariaos llm nvidia up/down` chiederà l'autenticazione amministrativa.

#### Scollegamento dell'eGPU

> [!CAUTION]
> Scollegamento **a freddo** soltanto. Eseguire `ariaos llm nvidia down` (che rimuove anche i device dal bus PCIe) prima di scollegare il cavo Thunderbolt. Non scollegare mai con il driver attivo.

#### Limiti di VRAM e offload

La RTX 3060 ha 12 GB di VRAM. Un modello più grande (es. Gemma 4 26B Q4_K_XL ≈ 14,2 GB) non ci sta interamente: il profilo CUDA va costruito con `--n-cpu-moe` (esperti in RAM, strati densi + KV cache in VRAM) o con un modello più piccolo. La scelta del profilo e del modello è tua, non dell'immagine.

### Backup e storage

- **Pika Backup**: backup incrementali quotidiani. È l'unica applicazione critica autorizzata come Flatpak (`org.gnome.World.PikaBackup`).
- **`backup`**: esporta `/var/home` come stream Btrfs compresso su un disco esterno.
- **`restore`**: valida e riceve lo stream, conserva la home precedente e tenta il rollback se l'attivazione fallisce.
- **`/var/games`**: subvolume separato dagli snapshot della home, gestito tramite `systemd-tmpfiles` e gruppo `aria-games`.

### Audio

`ariaos-daw-launcher` applica il profilo `latency-performance` soltanto durante la sessione DAW e ripristina automaticamente il profilo precedente. Non vengono usati kernel realtime di terze parti né parametri realtime permanenti.

### Kubernetes

L'immagine include:

- `kubectl`
- Helm
- Minikube
- `kubectx`
- `kubens`
- completamento Bash per kubectl e Minikube

Minikube è destinato al driver Podman rootless già presente. Non viene installato Docker e non viene avviato alcun cluster permanente.

## Installazione

Partendo da Fedora Silverblue installata con Btrfs e LUKS2:

```bash
sudo bootc switch ghcr.io/holden093/ariaos:latest
sudo reboot
```

Dopo il primo avvio, aggiungere l'utente ai gruppi richiesti:

```bash
sudo usermod -aG wheel,realtime,audio,aria-games,libvirt "$USER"
```

Terminare la sessione o riavviare affinché i nuovi gruppi siano applicati. Il gruppo `wheel` è necessario per la regola polkit che autorizza `ariaos llm nvidia up/down` senza password.

Per associare il volume root al TPM usando PCR 7, sostituire il device con quello reale verificato tramite `lsblk`:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3
```

PCR 8 e 9 non sono adatti a questo sistema: aggiornamenti `bootc` modificano kernel, riga di comando e initramfs e causerebbero richieste ricorrenti della passphrase di recupero.

### Configurare i backend di inferenza

L'immagine non contiene né modelli né motori. Il collegamento tra `ariaos llm` e i tuoi launcher avviene tramite un file di configurazione.

#### Schema e precedenza

Le variabili sono otto, quattro per backend:

| Variabile | Significato | Default |
|---|---|---|
| `INTEL_PORT` / `NVIDIA_PORT` | porta del server (solo informativa) | `8080` / `8081` |
| `INTEL_HEALTH` / `NVIDIA_HEALTH` | URL dell'health check interrogato da `status`, `up`, `down` | `http://127.0.0.1:PORT/health` |
| `INTEL_START` / `NVIDIA_START` | comando eseguito con `bash -c` per avviare il server (vuoto = non configurato) | *vuoto* |
| `INTEL_STOP` / `NVIDIA_STOP` | comando eseguito per arrestare il server | *vuoto* |

Precedenza: `/usr/lib/ariaos/llm.conf` (default distribuito, ripristinato dagli aggiornamenti) è letto per primo; `/etc/ariaos/llm.conf` è letto dopo e **sovrascrive**. Le tue personalizzazioni stanno solo in `/etc`, che è persistente tra gli aggiornamenti dell'immagine.

Configurazione iniziale:

```bash
sudo cp /usr/lib/ariaos/llm.conf /etc/ariaos/llm.conf
sudoedit /etc/ariaos/llm.conf
```

`START`/`STOP` girano **come utente** (il comando `ariaos` rifiuta root), quindi possono riferirsi a `$HOME` e ai toolbox personali. L'health check usa `curl -fsS -m 3`: l'endpoint deve rispondere con un codice 2xx (il `/health` di llama-server lo fa).

#### Esempio backend Intel (Arc / Vulkan)

Riuso del launcher già esistente, senza modifiche: il profilo Gemma su Arc resta quello che usi oggi.

```bash
INTEL_PORT=8080
INTEL_HEALTH=http://127.0.0.1:8080/health
INTEL_START=/home/kevin/GIT/test/gemma4-server start
INTEL_STOP=/home/kevin/GIT/test/gemma4-server stop
```

`ariaos llm intel up` esegue `bash -c "$INTEL_START"` e attende che `INTEL_HEALTH` risponda. Da quel momento `gemma4-server` resta disponibile anche direttamente; `ariaos llm` aggiunge solo mutua esclusione e stato unificato.

#### Esempio backend NVIDIA (eGPU / CUDA)

Richiede un llama.cpp **compilato con CUDA** in un container che riceva la GPU via CDI. La spec CDI è generata da `ariaos-egpu up` in `/run/cdi/nvidia.yaml`; Podman la consuma con `--device nvidia.com/gpu=all`. Nota: `toolbox run` non inietta device GPU, serve `podman run` (o distrobox).

Un launcher dedicato (es. `/home/kevin/bin/nvidia-llm`) con le solite azioni `start|stop|status`:

```bash
#!/usr/bin/env bash
# start avvia il server CUDA in un container con la GPU via CDI
case "${1:-start}" in
  start)
    podman run --rm -d --name nvidia-llm \
      --device nvidia.com/gpu=all \
      -v "$HOME/models:/models:ro" \
      -p 127.0.0.1:8081:8081 \
      <immagine-llama-cuda> \
      llama-server -m /models/... --n-gpu-layers 999 --port 8081
    ;;
  stop) podman rm -f nvidia-llm ;;
esac
```

Dichiararlo in `/etc/ariaos/llm.conf`:

```bash
NVIDIA_PORT=8081
NVIDIA_HEALTH=http://127.0.0.1:8081/health
NVIDIA_START=/home/kevin/bin/nvidia-llm start
NVIDIA_STOP=/home/kevin/bin/nvidia-llm stop
```

Ordine corretto per l'uso: `ariaos llm nvidia up` carica prima il driver e genera la spec CDI, poi esegue `NVIDIA_START`; se il container parte prima che `/run/cdi/nvidia.yaml` esista, il mount GPU fallisce.

#### Riepilogo d'uso

```bash
ariaos llm status        # verifica che un backend sia "non configurato", "fermo" o "attivo"
ariaos llm intel up      # mobilità: Gemma su Arc, porta 8080
ariaos llm nvidia up     # casa con enclosure: driver + CUDA, porta 8081
ariaos llm nvidia down   # prima di scollegare il cavo Thunderbolt
```

Se `status` riporta `non configurato`, il backend non ha ancora `START` valorizzato in `/etc/ariaos/llm.conf`.

## Struttura del repository

```text
Containerfile                 orchestrazione degli stage di build
build_files/                  filesystem finale dichiarativo
scripts/build/                mutazioni temporanee eseguite durante la build
scripts/validate/             controlli statici e contratto dell'immagine
tests/                        test operativi isolati con comandi simulati
versions/external-tools.env   versioni e checksum degli artefatti upstream
.github/workflows/            build e pubblicazione dell'immagine
AGENTS.md                     invarianti tecnici per gli agenti
```

I moduli in `scripts/build/` vengono montati da uno stage `scratch` e non rimangono nell'immagine finale.

## Sviluppo e validazione

Controlli rapidi:

```bash
./scripts/validate.sh
```

Validazione completa obbligatoria dopo modifiche a `Containerfile`, `build_files/`, moduli di build o dipendenze esterne:

```bash
./scripts/preflight.sh
```

Il preflight:

1. esegue controlli statici e test operativi non distruttivi;
2. costruisce l'intera immagine con Podman;
3. verifica pacchetti, strumenti, completamenti, servizi, maschere, permessi e policy GPU;
4. conferma che componenti ritirati e file di build non siano presenti.

GitHub Actions applica lo stesso contratto `scripts/validate/image.sh` all'immagine costruita.

## Licenza

AriaOS è distribuito secondo GNU GPL v3.0. Consultare [LICENSE](LICENSE).
