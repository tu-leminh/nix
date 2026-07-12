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

## Module map

```
modules/
  iso/default.nix        installer image (installation-cd-minimal-new-kernel-no-zfs + bcachefs + keyutils)
  disko/default.nix      the 5-disk bcachefs pool
  disko/tiering.nix      first-boot per-directory redundancy
  system/default.nix     bootloader, hostname, firewall off, timezone, base pkgs; imports the rest
  system/users.nix       root + mt (single-space passwords), ~/.ssh tmpfiles dir
  system/ssh.nix         openssh (no root login, password auth)
  system/network.nix     static enp6s0
  desktop/default.nix    GDM + GNOME + Sway + PipeWire
  k3s/default.nix        k3s server + kube tooling; imports argocd.nix + perm-fixer.nix
  k3s/argocd.nix         homelab-bootstrap service
  k3s/perm-fixer.nix     chown app hostPath dirs to uid/gid 1000 on inotify change
```

## Storage

One bcachefs filesystem (`pool`) spans all five devices, referenced by
`/dev/disk/by-id/*`. Device groups drive tiering:

| Group | Device | Role |
| --- | --- | --- |
| `nvme` | Crucial P3 2TB | ESP (`/boot`, FAT32 1G) + pool member, **no target** |
| `ssd` | WD Blue 500GB | `foreground_target` + `promote_target` |
| `hdd` ×3 | 1TB + 500GB + 2TB | `background_target` |

Pool format args: `--foreground_target=ssd --promote_target=ssd
--background_target=hdd --metadata_target=ssd --replicas=2 --erasure_code`.
No encryption, no compression.

Subvolumes → mounts: `root`→`/`, `data/tier1..3`→`/data/tier1..3`.

### Per-directory redundancy

`--replicas=2 --erasure_code` (raid5-style) is the format default, so `/` and
`/data/tier2` need nothing extra. `tiering.nix` runs a first-boot oneshot
(`bcachefs-tiering`, stamp `/var/lib/bcachefs-tiering.done`) that sets the rest
via `bcachefs setattr`, inherited by newly written files:

- `/data/tier1` → `--data_replicas=3 --erasure_code=1` (raid6-style)
- `/data/tier3` → `--data_replicas=1 --erasure_code=0`

**Constraints / gotchas:**
- **Never add `--casefold`** — casefolded dirents break overlayfs, which
  k3s/containerd needs for image layers. It's off by default; recheck on
  bcachefs/kernel updates.
- `replicas=3 + EC` over 3 HDDs is effectively 3-way mirroring (real raid6 wants
  ≥4 disks). Valid, tolerates 2 failures, no parity space savings.
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
- Firewall **off** (trusted home LAN) — so no k3s/MetalLB port rules are needed.
- `root` and `mt` both have `initialPassword = " "` (change on first boot).
  `mt` is in `wheel` + `networkmanager`.
- OpenSSH: `PermitRootLogin = no`, `PasswordAuthentication = true`.
- Timezone `Asia/Ho_Chi_Minh`.

## Desktop

GDM offers both GNOME and Sway (Wayland) at login. PipeWire (alsa+pulse),
`hardware.graphics`, fonts, and a small Sway toolkit (foot/wofi/waybar).

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
