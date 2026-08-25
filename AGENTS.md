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
- Shared configuration lives in `modules/`; hosts explicitly import each
  capability. NixOS-only display, hardware, and server policy remain host-local.
- A host adapts a shared module in one of four ways, best first: fill a typed
  option the module declares (`modules/home/vscode.nix` declares
  `executable`/`tunnelName`/`servicePath`); import only the capabilities it
  wants; set `_module.args.<key>` for a narrow override read as
  `config._module.args.<key> or <default>` (currently only
  `weztermFrontEnd`); or drop in a host-local file such as
  `xdg.configFile."xonsh/rc.d/…"`. Don't hardcode a machine fact in
  `modules/`, and don't add an untyped knob that no host sets.

## Purpose

One flake, three outputs:

- **`nixosConfigurations.installer`** — a minimal, bcachefs-enabled
  installation ISO.
- **`nixosConfigurations.homelab`** — the installed machine: a single
  bcachefs pool across 6 disks, GNOME with PaperWM tiling, and a single-node
  K3s cluster that bootstraps the private
  [argohome](https://github.com/tu-leminh/argohome) Argo CD GitOps stack.
- **`homeConfigurations."tu-le5@work-linux"`** — standalone home-manager (no
  NixOS) for an Ubuntu work laptop (nix as package manager + dotfiles): same
  shared user packages/dotfiles as homelab, no system-level config.

## Inputs / outputs

- Inputs: `nixpkgs` (nixos-unstable), `disko`, `home-manager`, `paperwm`
  (upstream's own flake, `inputs.nixpkgs.follows = "nixpkgs"`; there is no
  nixpkgs package for the PaperWM GNOME Shell extension, so this input
  packages it — see Desktop below).
- `nixosConfigurations.installer` → `.#iso` = `…build.isoImage`.
- `nixosConfigurations.homelab` (x86_64-linux, `stateVersion = "26.11"`).
- `homeConfigurations."tu-le5@work-linux"` (x86_64-linux).

## Layout

`hosts/` holds machine facts and `modules/` holds reusable NixOS and
Home Manager capabilities. Each host has only the applicable `nixos/` and
`home/` entrypoints. Outputs remain explicit in `flake.nix`.

```
hosts/
  homelab/nixos/default.nix  installed host composition; hostname and stateVersion
  homelab/nixos/installer.nix  homelab's bcachefs installation ISO
  homelab/nixos/storage.nix  standalone disko layout for the 5-disk pool
  homelab/nixos/k3s/         homelab-only K3s, Cilium, and Argo CD bootstrap
  homelab/home/default.nix   mt identity and selected shared home capabilities
  work-linux/home/default.nix  standalone Home Manager config for tu-le5
modules/
  nixos/                     base, GNOME + PaperWM, SSH, Home Manager integration
  home/                      base CLI tools plus GNOME/PaperWM and WezTerm capabilities
```

### Adding a machine

Create `hosts/<name>/nixos/default.nix` and/or `hosts/<name>/home/default.nix`,
import the selected capability modules, then add the explicit output in
`flake.nix`. Keep machine facts—identity, disks, IPs, hostname, and special
hardware—under `hosts/`.

## Storage

One bcachefs filesystem (`pool`) spans all six devices, referenced by
`/dev/disk/by-id/*`. Device groups drive tiering:

| Group | Device | Role |
| --- | --- | --- |
| `ssd.nvme0` | Crucial P3 2TB | ESP (`/boot`, FAT32 1G) + pool member, part of `ssd` group |
| `ssd.ssd0` | WD Blue 500GB | pool member, part of `ssd` group |
| `ssd.nvme1` | Samsung PM961 128GB | pool member, part of `ssd` group (added online post-install) |
| `hdd` ×3 | 1TB + 500GB + 2TB | pool members |

Device labels are dot-hierarchical (`ssd.ssd0`, `ssd.nvme0`); a target of
`ssd` matches every label starting with `ssd.`, so `metadata_target=ssd`
lands on both ssd and nvme. No other targets are set: the allocator spreads
data across every device by free space instead of a fixed hot/cold split.

Pool format args: `--metadata_target=ssd --replicas=2 --gc_reserve_percent=5`.
The 5% is the kernel-minimum copygc reserve (default 8% held back ~490 GB on
this pool); runtime-tunable via `bcachefs set-fs-option`, no reformat needed.
No erasure coding, encryption, or compression.

Subvolumes → mounts: `root`→`/`, `data/tier1..3`→`/data/tier1..3`.
`/var` is a plain dir in the root subvolume (no var subvolume in the layout —
its options are inode options, see below).

### Per-directory redundancy

`--replicas=2` (no EC) is the format default, so `/` and `/data/tier2` need
nothing extra. `storage-services.nix` runs a first-boot oneshot (`bcachefs-tiering`,
stamp `/var/lib/bcachefs-tiering.done`) that sets the rest via `bcachefs
set-file-option`, inherited by newly written files:

- `/data/tier1` → `--data_replicas=3 --erasure_code=0` (3-way mirror)
- `/data/tier3` → `--data_replicas=1 --erasure_code=0`
- `/var` → `--data_replicas=2 --foreground_target=ssd --erasure_code=0` —
  covers the whole subtree: k3s's embedded SQLite datastore + containerd
  layer extraction, journald, `/var/lib/homelab` — small latency-sensitive
  random I/O that the pool-wide default would spread across the slow HDDs.
  This supersedes the old per-dir `--foreground_target=ssd` lines for
  `/var/lib/rancher/k3s` and `/var/lib/kubelet`. `/var` is a plain dir in the
  root subvolume (no subvolume in the layout), so this sets inode options on
  the dir itself, inherited by newly written files below it.


**Constraints / gotchas:**
- **Never add `--casefold`** — casefolded dirents break overlayfs, which is
  unreliable on bcachefs anyway (k3s avoids it via `--snapshotter=native`,
  see K3s section below). Off by default; recheck on bcachefs/kernel updates.
- **EC was dropped** to cut write amplification on the slow/SMR HDDs (parity
  stripe RMW was a big source of I/O stalls). Plain replication only now.
- `replicas=3` over 3 HDDs is 3-way mirroring — tolerates 2 device failures at
  3× space cost.
- Changing disks = edit `by-id` paths + labels in `hosts/homelab/nixos/storage.nix`.

## Backup

`hosts/homelab/nixos/backup.nix`: `gdrive-backup.service` + matching `.timer` take
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

`hosts/homelab/nixos/network.nix` sets a NetworkManager static profile on `enp6s0`:
`10.0.0.100/16`, gateway + DNS `10.0.0.1`, `ipv4.method = manual` (no
DHCP). WiFi and other links stay NM-managed.

> The argohome Cilium LB-IPAM pool lives in a separate range
> (`10.0.1.2-10.0.1.255`), so it never overlaps the node address. The router
> forwards inbound 80/443 directly to the Gateway's LB IP (`10.0.1.2`), which
> Cilium L2-announces; the Gateway (reverse proxy) lives on a virtual
> LB-IPAM address, not the node IP. There is no node-side DNAT anymore: the
> former `homelab-dnat` double-NAT broke the reply path (the LB answers with
> `src 10.0.1.2` while the router's NAT expected replies from `10.0.0.100`).

## System

- systemd-boot + EFI; `boot.supportedFilesystems = [ "bcachefs" ]` on
  `linuxPackages_latest` (homelab's `nixos/default.nix`) — bcachefs is pre-stable and its on-disk
  format tracks the kernel, so the installed system must run the same recent
  kernel as the installer that formatted the pool, or `/` won't mount.
- `hardware.enableRedistributableFirmware` on — amdgpu (GPU/Vulkan), Intel
  Bluetooth, iwlwifi, and r8169 NIC blobs.
- Firewall **off** (trusted home LAN) — so no k3s/Cilium port rules are needed.
- `root` and `mt` both have `initialPassword = " "` (change on first boot).
  `mt` is in `wheel` + `networkmanager`, login shell is bash (the NixOS
  default — nothing sets `shell` anymore).
- OpenSSH: `PermitRootLogin = no`, `PasswordAuthentication = true`.
- Timezone `Asia/Ho_Chi_Minh`.

## Desktop

GNOME is the session on both machines, with PaperWM tiling. Waybar, Fuzzel,
Mango, and Noctalia are gone — no bar, launcher, or control-center config
exists in the flake; GNOME's own top bar, overview, and quick settings are
what you get, so the previous Nord/blue theme is gone too.

PaperWM is a GNOME Shell extension with no nixpkgs package, so the `paperwm`
flake input packages it (its `shell-version` is 45–50 and homelab's pinned
nixpkgs ships GNOME Shell 50.x; a future bump past 50 means switching the
input to a versioned upstream branch). Only the GDM registration differs by
host, because each machine's GNOME is started differently:

- **homelab** — `modules/nixos/gnome.nix` puts the extension in
  `environment.systemPackages` (the system profile lands it in
  `/run/current-system/sw/share/gnome-shell/extensions`, where GNOME Shell
  looks) and enables it for every user through
  `programs.dconf.profiles.user.databases`.
- **work-linux** — `modules/home/gnome.nix` symlinks the same store path into
  `~/.local/share/gnome-shell/extensions/` and enables it via
  `dconf.settings`. GDM starts GNOME outside the Nix profile there, so
  `XDG_DATA_DIRS` can't be relied on; the user extension dir always is
  scanned.

The two files can't be merged: a NixOS module and a Home Manager module
can't share one file. Server-only GNOME policy (no sleep/idle, trimmed
background services) stays host-local in
`hosts/homelab/nixos/gnome-policy.nix` — it is deliberately not folded into
the shared capability, so a future NixOS desktop host doesn't inherit it.

`modules/home/gnome-keys.nix` (both hosts) carries Mango's keybindings over
via dconf: PaperWM actions, fixed 9 workspaces (Ctrl+N view, Alt+N move
window), launcher/screenshot/lock, and `Alt+Return` for WezTerm. PaperWM and
GNOME defaults that collide are cleared there. Mango-only features (layout
switching, gaps, minimize, pixel move/resize, float) have no equivalent.

Home Manager's Generic Linux target exposes Ubuntu's Mesa/EGL runtime to all
Nix GUI apps via `/run/opengl-driver`.

CLI/TUI tools (neovim, lazygit, superfile, claude-code, codex, antigravity-ide,
opencode, uv, btop, k9s, kubectl, helm, argocd, herdr, xonsh, fzf) and chrome
live in `modules/home/base.nix`, along with the shells and zoxide wiring
below; `allowUnfree` lives in `modules/nixos/base.nix`.

### Shells: bash, xonsh, zoxide

`modules/home/base.nix` owns the shell setup for both machines:

- `programs.bash.enable` — GNOME Terminal is bash on both hosts. Enabling it
  also activates the `targets.genericLinux` hook that sources `nix.sh` and
  `hm-session-vars.sh`; that hook is `mkIf programs.bash.enable`, so on the
  Ubuntu laptop it was silently dead before this. Note HM takes full
  ownership of `~/.bashrc`, so the laptop needs a one-time
  `mv ~/.bashrc ~/.bashrc.backup` (see `README.md`).
- `xonsh` is only a WezTerm `default_prog`, never the system login shell.
- `programs.zoxide.enable` with default options: `z`/`zi` sit next to a normal
  `cd`, it is not aliased over it. The bash hook is automatic; there is no
  `enableXonshIntegration`, so `~/.xonshrc` is written by hand with upstream's
  `execx($(zoxide init xonsh), …)` and an absolute store path. `fzf` backs
  `zi`'s interactive picker.

Hosts add host-specific shell values as xonsh `rc.d` drop-ins
(`xdg.configFile."xonsh/rc.d/…"`) rather than editing `~/.xonshrc`, which the
shared module owns — that's where the `rebuild` alias lives.

## K3s + Cilium + Argo CD bootstrap

`hosts/homelab/nixos/k3s/default.nix`: `services.k3s` server with
`--disable=traefik --disable=servicelb --write-kubeconfig-mode=0644
--snapshotter=stargz --flannel-backend=none --disable-network-policy
--disable-kube-proxy --cluster-cidr=10.42.0.0/16,fd42:42::/56
--service-cidr=10.43.0.0/16,fd42:43::/112`. Flannel/kube-proxy/the bundled
Traefik+servicelb are all disabled because Cilium (below) replaces every one
of them - CNI, kube-proxy (eBPF), LoadBalancer, and ingress. Cluster/service
CIDRs are dual-stack: IPv4 + an internal-only ULA range (RFC 4193) for pod/
service IPv6 - unrelated to the LAN's real `/64`, which only backs
LB-IPAM/Gateway external addresses (see argohome's `apps/infra/network`).
`KUBECONFIG` is exported system-wide; host tools: `kubectl`,
`kubernetes-helm`, `argocd`, `k9s`.

`hosts/homelab/nixos/k3s/cilium.nix`: `homelab-cilium-bootstrap.service` (oneshot,
`RemainAfterExit`, after `k3s`, **before** `homelab-bootstrap`). Cilium *is*
the CNI, so no pod - including Argo CD's own - can schedule until it's
running; that's why this can't be GitOps-managed and must run first, unlike
the LB-IPAM pool/L2Announcement/Gateway/HTTPRoutes, which stay in argohome
(`apps/infra/network`). Idempotent (`kubectl apply` + `helm upgrade
--install`): installs the Gateway API CRDs, then Cilium itself with
`kubeProxyReplacement`, dual-stack, `l2announcements`, and `gatewayAPI` all
enabled, pointed at this node's own API server (`k8sServiceHost`/`Port`,
since kube-proxy's Service routing is gone).

`hosts/homelab/nixos/k3s/argocd.nix`: `homelab-bootstrap.service` (oneshot,
`RemainAfterExit`, after `k3s` + `network-online` + `homelab-cilium-bootstrap`,
and `requires` the latter - if Cilium bootstrap fails, this should too rather
than proceed against a brokenly-networked cluster). It is idempotent and
self-healing:

1. If `/home/mt/.ssh/id_ed25519` is missing → log a hint and exit 0 (so the box
   boots; re-run with `systemctl restart homelab-bootstrap` after copying it).
2. Wait for the API (`kubectl get --raw=/readyz`).
3. Install Argo CD only if `deploy/infra-argocd-server` doesn't exist yet —
   `helm upgrade --install infra-argocd argo/argo-cd -n infra --create-namespace`
   with `server.service.type=LoadBalancer` and `server.insecure=true`. Skipped
   once present so a re-run can't lose a server-side-apply ownership fight
   with Argo CD's own controller. (Argo CD lives in `infra` — argohome's
   `apps/core` and `apps/tailscale` were merged into `apps/infra`, one
   namespace for everything except `media`.)
4. Create the Argo CD repository Secret `repo-argohome` (label
   `argocd.argoproj.io/secret-type=repository`) from the SSH key —
   `url = git@github.com:tu-leminh/argohome.git`, no token.
5. Clone/pull argohome to `/var/lib/homelab/argohome` and
   `kubectl apply` `bootstrap/applicationset.yaml`.

After that Argo CD pulls argohome itself (~3 min poll); no host cron. Argo
CD's own LoadBalancer Service (and everything else's) sits Pending until
argohome's `apps/infra/network` syncs in and provides the `10.0.1.2-255` pool
IPs. The router forwards inbound 80/443 to the Gateway's LB IP (`10.0.1.2`)
so external traffic reaches Envoy; other inbound ports that were previously
covered by the old blanket DMZ to `10.0.0.100` need their own router
forwards (e.g. the q1/q2/q3 torrent NodePorts 31081-31083).

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
- The VS Code tunnel's GitHub token (`modules/home/vscode.nix`), created via
  an interactive `code tunnel user login` on each machine itself.
- The Google Drive `rclone.conf` (`backup.nix`), created via an interactive
  `sudo rclone config` on the box itself — no separate machine or file copy.

Trade-off shared by all three: none are restored automatically on
reinstall; re-do each once.

## Validation

```
nix eval .#nixosConfigurations.homelab.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.installer.config.system.build.isoImage.drvPath
nix build .#iso
nix build .#homeConfigurations."tu-le5@work-linux".activationPackage
```
