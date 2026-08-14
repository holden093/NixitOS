# AriaOS

AriaOS è un sistema operativo personale, immutabile e dichiarativo basato su Fedora Silverblue 44, `bootc` e `blue-build`.

> [!WARNING]
> Questa immagine è progettata per uno specifico laptop Intel Lunar Lake con eGPU NVIDIA Thunderbolt. Non è una distribuzione generica e può essere inadatta o pericolosa su hardware diverso.

## Obiettivi

- Sistema riproducibile: ogni modifica persistente vive nel repository.
- Base nativa essenziale, con Flatpak e Distrobox per applicazioni non critiche.
- Intel Arc sempre disponibile per desktop, media e calcolo OpenCL/Level Zero.
- eGPU NVIDIA mai inizializzata dall'host (riservata a vfio-pci) e usata solo da una VM dedicata come endpoint OpenAI locale.
- Backup giornalieri e ripristino bare-metal indipendenti.
- Buona autonomia nell'uso normale e tuning dinamico per sessioni audio.

## Piattaforma

| Area | Configurazione |
|---|---|
| Base | Fedora Silverblue 44, `bootc`, `blue-build` |
| Desktop | GNOME Wayland con tema Yaru |
| GPU primaria | Intel Arc Lunar Lake |
| GPU secondaria | NVIDIA eGPU Thunderbolt, riservata a vfio-pci e passata a una VM |
| VM IA | `llama-vm`: 2 vCPU / 4 GiB, headless, endpoint OpenAI su `127.0.0.1:8080` |
| Storage | Btrfs con compressione `zstd:1` |
| Cifratura | LUKS2, TPM 2.0 e Discoverable Partitions Specification |
| Memoria | 32 GB RAM, zRAM da 16 GB con `zstd` |

## Funzionalità principali

### GPU e calcolo

Intel Arc dispone di `intel-compute-runtime`, `intel-level-zero`, OpenCL e strumenti Vulkan per desktop, media e calcolo, senza alcun motore LLM host-side.

La eGPU NVIDIA (RTX 3060 `10de:2504` + audio `10de:228e`) è **riservata a `vfio-pci`** tramite i kernel arguments (`vfio-pci.ids=`, `pcie_acs_override=downstream`) e una regola udev: l'host non la inizializza mai, non carica driver NVIDIA e la passa per intero alla VM `llama-vm`. La riserva è per vendor/device, quindi cambiare porta Thunderbolt non richiede modifiche.

> [!CAUTION]
> Scollegamento a freddo: fermare prima la VM con `sudo llama-vm off`. Non scollegare mai l'enclosure mentre la VM è in esecuzione.

### VM AI (llama-vm)

`llama-vm` è una macchina virtuale headless (2 vCPU / 4 GiB) che esegue llama.cpp come endpoint compatibile OpenAI su `http://127.0.0.1:8080/v1`. I modelli GGUF vivono sull'host in `/var/vms/models` (subvolume Btrfs) e sono montati read-only nella VM via virtiofs.

Uso quotidiano:

```bash
sudo llama-vm status   # stato eGPU, dominio ed endpoint
sudo llama-vm on       # verifica vfio-pci, definisce/aggiorna il dominio, avvia e attende l'endpoint
sudo llama-vm off      # spegne la VM (poi si può scollegare la eGPU)
```

Aggiungere un modello:

```bash
sudo guest/fetch-model.sh https://example.com/modello.gguf SHA256 # opzionale
sudo llama-vm off && sudo llama-vm on
```

Provisioning iniziale (una tantum, dopo aver aggiornato l'immagine):

```bash
sudo guest/build.sh        # costruisce /var/vms/llama/llama.qcow2 (bootc-image-builder)
sudo guest/install-vm.sh   # crea /var/vms/models, definisce e avvia la VM
sudo guest/fetch-model.sh <URL-del-gguf>
```

La guest è un appliance Fedora fisso (kernel pinnato via `excludepkgs=kernel*`); il modulo NVIDIA viene compilato alla creazione dell'immagine. Chiave SSH/console: `sudo virsh -c qemu:///system console llama-vm`.

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
sudo usermod -aG realtime,audio,aria-games,libvirt "$USER"
```

Terminare la sessione o riavviare affinché i nuovi gruppi siano applicati.

Per associare il volume root al TPM usando PCR 7, sostituire il device con quello reale verificato tramite `lsblk`:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3
```

PCR 8 e 9 non sono adatti a questo sistema: aggiornamenti `bootc` modificano kernel, riga di comando e initramfs e causerebbero richieste ricorrenti della passphrase di recupero.

## Struttura del repository

```text
Containerfile                 orchestrazione degli stage di build
build_files/                  filesystem finale dichiarativo
scripts/build/                mutazioni temporanee eseguite durante la build
scripts/validate/             controlli statici e contratto dell'immagine
tests/                        test operativi isolati con comandi simulati
versions/external-tools.env   versioni e checksum degli artefatti upstream
guest/                        provisioning della VM AI: Containerfile, versioni e script build/install/fetch
.github/workflows/            build e pubblicazione dell'immagine
AGENTS.md                     invarianti tecnici per gli agenti
```

I moduli in `scripts/build/` vengono montati da uno stage `scratch` e non rimangono nell'immagine finale. La guest AI è riproducibile da `guest/` ma la sua costruzione non fa parte del preflight host (QEMU/KVM, rete e download).

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
