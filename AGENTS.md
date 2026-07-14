# AGENTS.md

Technical reference for this flake. User-facing steps live in
[README.md](README.md).

## Conventions

- KISS: prefer the simplest thing that works over clever abstractions.
- Fewer files grouped by functionality beats many small ones — split a file
  only when it holds genuinely unrelated concerns.
- Reuse existing modules/options instead of duplicating config.
- Comments are short and explain *why*, not what — the Nix itself should read
  clearly enough that a longer, obvious block is preferred over a terse,
  cryptic one.

## Purpose

One flake, four outputs:

- **`nixosConfigurations.installer`** — a minimal, bcachefs-enabled
  installation ISO.
- **`nixosConfigurations.homelab`** — the installed machine: a single
  bcachefs pool across 5 disks, GNOME + Sway, and a single-node K3s cluster
  that bootstraps the private
  [argohome](https://github.com/tu-leminh/argohome) Argo CD GitOps stack.
- **`homeConfigurations."mt@work-linux"`** — standalone home-manager (no
  NixOS) for an Ubuntu work laptop: same user packages/dotfiles as homelab,
  no system-level config.
- **`hosts/work-mac`** — empty placeholder for a future nix-darwin machine;
  not wired into `flake.nix` yet.

## Inputs / outputs

- Inputs: `nixpkgs` (nixos-unstable), `disko`, `home-manager`.
- `nixosConfigurations.installer` → `.#iso` = `…build.isoImage`.
- `nixosConfigurations.homelab` (x86_64-linux, `stateVersion = "26.11"`).
- `homeConfigurations."mt@work-linux"` (x86_64-linux).

## Layout

`hosts/` holds everything unique to one machine; `modules/` holds host-agnostic
NixOS capabilities; `user/` holds the home-manager config shared by every
machine (system or standalone). Unlike a generate-from-folder setup, each
output in `flake.nix` is listed explicitly — adding a host means adding both
the folder *and* a `flake.nix` entry.

```
hosts/
  homelab/default.nix        imports modules + host nix files; hostname, stateVersion
  homelab/storage.nix        the 5-disk bcachefs pool layout (disko.devices only, no pkgs);
                              fed to the disko CLI standalone during install
  homelab/storage-services.nix  first-boot per-directory redundancy and SMART monitoring
                              (the pkgs/NixOS-only storage bits); imported alongside storage.nix
  homelab/network.nix        static enp6s0 (192.168.1.100)
  homelab/swap.nix           zram swap (raw NVMe swap partition lives in storage.nix)
  homelab/vscode-tunnel.nix  VS Code tunnel remote access (nix-ld)
  homelab/backup.nix         weekly rclone snapshot of /data/tier1+tier2 to Google Drive
  homelab/k3s/default.nix    k3s server + kube tooling; imports argocd.nix
  homelab/k3s/argocd.nix     homelab-bootstrap service (Argo CD + argohome)
  installer/default.nix      standalone installer ISO (installation-cd-graphical-gnome + bcachefs)
  work-linux/home.nix        standalone home-manager; imports ../../user/default.nix
  work-mac/default.nix       empty placeholder, not wired into flake.nix
modules/
  base.nix                   bootloader, NetworkManager, firewall off, timezone, base pkgs, users, ssh
  desktop.nix                GDM + GNOME + Sway + PipeWire + Sway UI toolkit; server no-sleep policy
  home.nix                   wires home-manager into NixOS; home-manager.users.mt = ../user/default.nix
user/
  default.nix                mt's home-manager config: nushell, git, dev tools/apps (shared by every host)
```

### Adding a machine

Create `hosts/<name>/default.nix` (NixOS) or `hosts/<name>/home.nix`
(standalone home-manager) importing `../../modules/base.nix` plus whichever
capability modules apply, set `networking.hostName` and
`system.stateVersion`, and add per-host disk/network files. Then add the
matching output in `flake.nix` — it is not generated automatically. Keep
`modules/` free of host assumptions (IPs, disk ids, hostname).

## Storage

One bcachefs filesystem (`pool`) spans all five devices, referenced by
`/dev/disk/by-id/*`. Device groups drive tiering:

| Group | Device | Role |
| --- | --- | --- |
| `ssd.nvme0` | Crucial P3 2TB | ESP (`/boot`, FAT32 1G) + pool member, part of `ssd` group for `metadata_target` only — **not** `foreground_target`/`promote_target` |
| `ssd.ssd0` | WD Blue 500GB | `foreground_target` + `promote_target` (device-specific) **and** part of `ssd` group for `metadata_target` |
| `hdd` ×3 | 1TB + 500GB + 2TB | `background_target` |

Device labels are dot-hierarchical (`ssd.ssd0`, `ssd.nvme0`); a target of
`ssd` matches every label starting with `ssd.`, so `metadata_target=ssd`
lands on both ssd and nvme, while `foreground_target=ssd.ssd0` and
`promote_target=ssd.ssd0` are the full, unique label of the ssd device and
so match only it.

Pool format args: `--foreground_target=ssd.ssd0 --promote_target=ssd.ssd0
--background_target=hdd --metadata_target=ssd --replicas=2`.
No erasure coding, encryption, or compression.

Subvolumes → mounts: `root`→`/`, `data/tier1..3`→`/data/tier1..3`.

### Per-directory redundancy

`--replicas=2` (no EC) is the format default, so `/` and `/data/tier2` need
nothing extra. `storage-services.nix` runs a first-boot oneshot (`bcachefs-tiering`,
stamp `/var/lib/bcachefs-tiering.done`) that sets the rest via `bcachefs
set-file-option`, inherited by newly written files:

- `/data/tier1` → `--data_replicas=3 --erasure_code=0` (3-way mirror)
- `/data/tier3` → `--data_replicas=1 --erasure_code=0`

**Constraints / gotchas:**
- **Never add `--casefold`** — casefolded dirents break overlayfs, which is
  unreliable on bcachefs anyway (k3s avoids it via `--snapshotter=native`,
  see K3s section below). Off by default; recheck on bcachefs/kernel updates.
- **EC was dropped** to cut write amplification on the slow/SMR HDDs (parity
  stripe RMW was a big source of I/O stalls). Plain replication only now.
- `replicas=3` over 3 HDDs is 3-way mirroring — tolerates 2 device failures at
  3× space cost.
- Changing disks = edit `by-id` paths + labels in `hosts/homelab/storage.nix`.

## Backup

`hosts/homelab/backup.nix`: `gdrive-backup.service` + matching `.timer` take
a weekly (Sun 03:00) snapshot of `/data/tier1` and `/data/tier2` to Google
Drive via `rclone`. Each source path is mirrored as-is (not collapsed to a
basename) under a dated folder, e.g. `/data/tier1` →
`gdrive:backup/<YYYYMMDD>/data/tier1`, so the Drive layout is unambiguous and
restore is a straight mirror back. A prune step keeps only the newest 4
dated folders (current + 3 previous) — `dirs`, `keep`, and `schedule` are
plain `let`-bound variables at the top of the file, meant to be the only
things edited when tuning this.

Restore is manual, on demand: `systemctl start
gdrive-restore@<date-or-latest>.service` (a template unit, never
auto-started) pulls a given dated snapshot — or the most recent one — back
down to the same local paths.

Both units gate on `/root/.config/rclone/rclone.conf` existing
(`ConditionPathExists`, skips cleanly rather than failing if it's missing)
— see "Secrets" below for how that file gets there.

## Network

`hosts/homelab/network.nix` sets a NetworkManager static profile on `enp6s0`:
`192.168.1.100/24`, gateway + DNS `192.168.1.1`, `ipv4.method = manual` (no
DHCP). WiFi and other links stay NM-managed.

> `192.168.1.100` is the first IP of argohome's MetalLB pool
> (`192.168.1.100-200`) — move the node IP out of the range or start the pool at
> `.101` to avoid a clash.

## System

- systemd-boot + EFI; `boot.supportedFilesystems = [ "bcachefs" ]` on
  `linuxPackages_latest` (base.nix) — bcachefs is pre-stable and its on-disk
  format tracks the kernel, so the installed system must run the same recent
  kernel as the installer that formatted the pool, or `/` won't mount.
- `hardware.enableRedistributableFirmware` on — amdgpu (GPU/Vulkan), Intel
  Bluetooth, iwlwifi, and r8169 NIC blobs.
- Firewall **off** (trusted home LAN) — so no k3s/MetalLB port rules are needed.
- `root` and `mt` both have `initialPassword = " "` (change on first boot).
  `mt` is in `wheel` + `networkmanager`, login shell is nushell.
- OpenSSH: `PermitRootLogin = no`, `PasswordAuthentication = true`.
- Timezone `Asia/Ho_Chi_Minh`.

## Desktop

GDM offers both GNOME and Sway (Wayland) at login. PipeWire (alsa+pulse),
`hardware.graphics`, Bluetooth (`hardware.bluetooth`, power-on-boot), fonts, and
a small Sway toolkit (foot/wofi/waybar).
Because this box is a server, `desktop.nix` disables all auto-sleep: GDM
`autoSuspend = false`, the systemd sleep/suspend/hibernate/hybrid-sleep targets
are off, and a dconf profile sets GNOME's idle power actions to "nothing".

User apps and dev tools (wezterm, firefox, neovim, lazygit, claude-code) live
in `user/default.nix` (home-manager), shared by every host so they're easy to
trim in one place; `allowUnfree` lives in `modules/base.nix`.

## K3s + Argo CD bootstrap

`hosts/homelab/k3s/default.nix`: `services.k3s` server with
`--disable=traefik --disable=servicelb --write-kubeconfig-mode=0644` (argohome
ships its own Traefik + MetalLB) and `--snapshotter=native` (overlayfs on
bcachefs is unreliable for containerd's image layers; native trades disk
space/pull time to avoid it). `KUBECONFIG` is exported system-wide; host
tools: `kubectl`, `kubernetes-helm`, `argocd`, `k9s`.

`hosts/homelab/k3s/argocd.nix`: `homelab-bootstrap.service` (oneshot,
`RemainAfterExit`, after `k3s` + `network-online`). It is idempotent and
self-healing:

1. If `/home/mt/.ssh/id_ed25519` is missing → log a hint and exit 0 (so the box
   boots; re-run with `systemctl restart homelab-bootstrap` after copying it).
2. Wait for the API (`kubectl get --raw=/readyz`).
3. Install Argo CD only if `deploy/argocd-server` doesn't exist yet —
   `helm upgrade --install argocd argo/argo-cd -n core --create-namespace`
   with `server.service.type=LoadBalancer` and `server.insecure=true`. Skipped
   once present so a re-run can't lose a server-side-apply ownership fight
   with Argo CD's own controller.
4. Create the Argo CD repository Secret `repo-argohome` (label
   `argocd.argoproj.io/secret-type=repository`) from the SSH key —
   `url = git@github.com:tu-leminh/argohome.git`, no token.
5. Clone/pull argohome to `/var/lib/homelab/argohome` and
   `kubectl apply` `bootstrap/applicationset.yaml`.

After that Argo CD pulls argohome itself (~3 min poll); no host cron.

### Volume permissions

argohome's app config volumes are **static `hostPath` PVs** (storageClass
`local-storage`) backed by `/data/tier2/configs/<app>`. Two consequences that
bite pods running as a fixed non-root UID (autobrr, qui, seerr, sftpgo, slskd,
upbrr — all uid 1000):

- **`fsGroup` does nothing here.** Kubelet's `fsGroup` ownership management is
  skipped for `hostPath`/`local` volumes, so a pod-level `fsGroup: 1000` never
  chowns the mounted dir. (The `*arr` apps only work because their LinuxServer
  images start as root and chown the dir themselves via PUID/PGID.)
- **A kubelet `UMask` override doesn't help either** — it only affects dirs
  kubelet *auto-creates*, but these dirs are pre-created root:root `0755`.

Fix lives in argohome, not here: each affected chart's `deployment.yaml` runs a
root `initContainer` (`busybox`, `runAsUser: 0`) that `chown -R 1000:1000`s the
config mount before the app container starts. Add one whenever a new non-root
app gets a `hostPath`-backed config PVC.

## Secrets

No sops/agenix. Credentials are imperative state, not in the flake:

- The argohome deploy key, placed by hand at `~/.ssh/id_ed25519`. Its public
  key must be a read-only Deploy key on the private argohome repo.
- The VS Code tunnel's GitHub token (`vscode-tunnel.nix`), created via an
  interactive `code tunnel user login` on the box itself.
- The Google Drive `rclone.conf` (`backup.nix`), created via an interactive
  `sudo rclone config` on the box itself — no separate machine or file copy.

Trade-off shared by all three: none are restored automatically on
reinstall; re-do each once.

## Validation

```
nix eval .#nixosConfigurations.homelab.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.installer.config.system.build.isoImage.drvPath
nix build .#iso
```
