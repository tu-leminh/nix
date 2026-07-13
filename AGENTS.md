# AGENTS.md

Technical reference for this flake. User-facing steps live in
[README.md](README.md).

## Purpose

Two NixOS configurations from one flake:

- **`installer`** — a minimal, bcachefs-enabled installation ISO.
- **`homelab`** — the installed machine: a single bcachefs pool across 5 disks,
  GNOME + Sway, and a single-node K3s cluster that bootstraps the private
  [argohome](https://github.com/tu-leminh/argohome) Argo CD GitOps stack.

## Inputs / outputs

- Inputs: `nixpkgs` (nixos-unstable), `disko`.
- `nixosConfigurations.installer` → `.#iso` = `…build.isoImage`.
- `nixosConfigurations.homelab` (x86_64-linux, `stateVersion = "26.11"`).

## Layout

`hosts/` holds everything unique to one machine; `modules/` holds host-agnostic
capabilities. `flake.nix` turns every directory under `hosts/` into a
`nixosConfigurations.<name>` automatically (add a machine = add a folder), plus
the standalone `installer` ISO. Each host's `default.nix` imports the modules it
wants and sets its own hostname/stateVersion.

```
hosts/
  homelab/default.nix    imports modules + host specifics (hostname, stateVersion)
  homelab/disk.nix       the 5-disk bcachefs pool; imports tiering.nix
  homelab/tiering.nix    first-boot per-directory redundancy
  homelab/network.nix    static enp6s0 (192.168.1.100)
modules/
  base.nix               bootloader, NetworkManager, firewall off, timezone, base pkgs; imports users + ssh
  users.nix              root + mt (single-space passwords, nushell login shell), ~/.ssh tmpfiles dir
  ssh.nix                openssh (no root login, password auth)
  desktop.nix            GDM + GNOME + Sway + PipeWire + Sway UI toolkit; server no-sleep policy
  apps.nix               user apps + dev tools (wezterm, firefox, neovim, lazygit, claude-code); allowUnfree
  iso.nix                installer image (installation-cd-graphical-gnome + bcachefs + keyutils)
  k3s/default.nix        k3s server + kube tooling; imports argocd.nix + perm-fixer.nix
  k3s/argocd.nix         homelab-bootstrap service
  k3s/perm-fixer.nix     chown app hostPath dirs to uid/gid 1000 on inotify change
```

### Adding a machine

Create `hosts/<name>/default.nix` importing `../../modules/base.nix` plus
whichever capability modules apply, set `networking.hostName` and
`system.stateVersion`, and add per-host disk/network files. No `flake.nix` edit
needed. Keep `modules/` free of host assumptions (IPs, disk ids, hostname).

## Storage

One bcachefs filesystem (`pool`) spans all five devices, referenced by
`/dev/disk/by-id/*`. Device groups drive tiering:

| Group | Device | Role |
| --- | --- | --- |
| `nvme` | Crucial P3 2TB | ESP (`/boot`, FAT32 1G) + pool member, **no target** |
| `ssd` | WD Blue 500GB | `foreground_target` + `promote_target` |
| `hdd` ×3 | 1TB + 500GB + 2TB | `background_target` |

Pool format args: `--foreground_target=ssd --promote_target=ssd
--background_target=hdd --metadata_target=ssd --replicas=2`.
No erasure coding, encryption, or compression.

Subvolumes → mounts: `root`→`/`, `data/tier1..3`→`/data/tier1..3`.

### Per-directory redundancy

`--replicas=2` (no EC) is the format default, so `/` and `/data/tier2` need
nothing extra. `tiering.nix` runs a first-boot oneshot (`bcachefs-tiering`,
stamp `/var/lib/bcachefs-tiering.done`) that sets the rest via `bcachefs
set-file-option`, inherited by newly written files:

- `/data/tier1` → `--data_replicas=3 --erasure_code=0` (3-way mirror)
- `/data/tier3` → `--data_replicas=1 --erasure_code=0`

**Constraints / gotchas:**
- **Never add `--casefold`** — casefolded dirents break overlayfs, which
  k3s/containerd needs for image layers. It's off by default; recheck on
  bcachefs/kernel updates.
- **EC was dropped** to cut write amplification on the slow/SMR HDDs (parity
  stripe RMW was a big source of I/O stalls). Plain replication only now.
- `replicas=3` over 3 HDDs is 3-way mirroring — tolerates 2 device failures at
  3× space cost.
- Changing disks = edit `by-id` paths + labels in `disko/default.nix`.

## Network

`system/network.nix` sets a NetworkManager static profile on `enp6s0`:
`192.168.1.100/24`, gateway + DNS `192.168.1.1`, `ipv4.method = manual` (no
DHCP). WiFi and other links stay NM-managed.

> `192.168.1.100` is the first IP of argohome's MetalLB pool
> (`192.168.1.100-200`) — move the node IP out of the range or start the pool at
> `.101` to avoid a clash.

## System

- systemd-boot + EFI; `boot.supportedFilesystems = [ "bcachefs" ]`.
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

User apps and dev tools are split into `apps.nix` (wezterm, firefox, neovim,
lazygit, claude-code) so they're easy to trim; `allowUnfree` lives there too.

## K3s + Argo CD bootstrap

`k3s/default.nix`: `services.k3s` server with
`--disable=traefik --disable=servicelb --write-kubeconfig-mode=0644` (argohome
ships its own Traefik + MetalLB). `KUBECONFIG` is exported system-wide; host
tools: `kubectl`, `kubernetes-helm`, `argocd`, `k9s`.

`k3s/argocd.nix`: `homelab-bootstrap.service` (oneshot, `RemainAfterExit`,
after `k3s` + `network-online`). It is idempotent and self-healing:

1. If `/home/mt/.ssh/id_ed25519` is missing → log a hint and exit 0 (so the box
   boots; re-run with `systemctl restart homelab-bootstrap` after copying it).
2. Wait for the API (`kubectl get --raw=/readyz`).
3. `helm upgrade --install argocd argo/argo-cd -n core --create-namespace`
   with `server.service.type=LoadBalancer` and `server.insecure=true`.
4. Create the Argo CD repository Secret `repo-argohome` (label
   `argocd.argoproj.io/secret-type=repository`) from the SSH key —
   `url = git@github.com:tu-leminh/argohome.git`, no token.
5. Clone/pull argohome to `/var/lib/homelab/argohome` and
   `kubectl apply` `bootstrap/applicationset.yaml`.

After that Argo CD pulls argohome itself (~3 min poll); no host cron.

## Secrets

No sops/agenix. The single credential — the argohome deploy key — is placed on
the machine by hand at `~/.ssh/id_ed25519` (imperative state, not in the flake).
Its public key must be a read-only Deploy key on the private argohome repo.
Trade-off: not restored automatically on reinstall; re-copy once.

## Validation

```
nix eval .#nixosConfigurations.homelab.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.installer.config.system.build.isoImage.drvPath
nix build .#iso
```
