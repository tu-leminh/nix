# nix

Bcachefs installer ISO + a tiered 6-disk NixOS home-lab host (K3s + Argo CD),
plus a standalone home-manager setup for an Ubuntu work laptop.
Architecture and design notes: see [AGENTS.md](AGENTS.md).

## 1. Build the installer ISO

On any machine with Nix + flakes:

```
nix build .#iso
```

## 2. Write it to a USB stick

`/dev/sdX` is the USB stick — **not** an install disk:

```
sudo dd if=./result/iso/nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## 3. Install

Boot the USB first. This **erases all 6 disks** (wipes any existing OS):

```
# rm first so a retry after a failed attempt re-pulls the latest code
# (`git clone` into an existing /tmp/nix errors out and keeps the stale copy)
rm -rf /tmp/nix
git clone https://github.com/tu-leminh/nix.git /tmp/nix
sudo nix --extra-experimental-features 'nix-command flakes' run \
  github:nix-community/disko/latest -- --mode disko /tmp/nix/hosts/homelab/nixos/storage.nix
sudo nixos-install --flake /tmp/nix#homelab
reboot
```

## 4. First login

Log in as `mt` (or `root`); password is a single space. Change it:

```
passwd
```

Installs made before `--gc_reserve_percent=5` landed in `storage.nix` still
carry the 8% default; apply the smaller reserve once to the running
filesystem (persists in the superblock, no reformat):

```
# any pool member partition; persists in the superblock, no reformat
sudo bcachefs set-fs-option --gc_reserve_percent=5 \
  "$(findmnt -no SOURCE / | cut -d: -f1)"
```

## 5. Start the GitOps stack

Copy your SSH deploy key onto the box, then kick the bootstrap:

```
chmod 600 ~/.ssh/id_ed25519
sudo systemctl restart homelab-bootstrap
```

Add the matching **public** key as a read-only **Deploy key** on the `argohome`
repo. Verify:

```
systemctl status homelab-bootstrap
kubectl -n infra get applications
```

## 6. VS Code Remote Tunnel (optional)

Both machines run a persistent, user-owned VS Code tunnel once configured.
It makes an **outbound** connection, so it needs no router or firewall rule.
Open VS Code's Remote Explorer (or `https://vscode.dev`), sign in with the
same GitHub account, and connect to `homelab` or `work-linux`.

The tunnel token is imperative state at `~/.vscode/cli/token.json`. It must
remain readable only by its owner and must be recreated after a reinstall or
if it is deleted. The service intentionally uses this file rather than GNOME
Keyring: a service that starts before graphical login cannot unlock the
keyring.

### Homelab (NixOS)

The NixOS configuration supplies VS Code, `nix-ld`, user lingering, and the
service. After applying the configuration, log in as `mt` and authenticate it:

```
sudo nixos-rebuild switch --flake ~/nix#homelab
export VSCODE_CLI_USE_FILE_KEYCHAIN=1
code tunnel user login --provider github
chmod 600 ~/.vscode/cli/token.json
systemctl --user enable --now code-tunnel.service
```

Confirm that it is healthy and that it will survive reboot without a desktop
login:

```
systemctl --user status code-tunnel.service
loginctl show-user mt -p Linger
journalctl --user -u code-tunnel.service -f
```

`Linger=yes` is expected. Do not run `code tunnel service install`; Home
Manager owns the unit so upgrades remain declarative.

### Work laptop (Ubuntu)

Ubuntu owns the VS Code package; Nix/Home Manager only manages the tunnel
unit. First install the official Microsoft APT source and stable `code`
package:

```
sudo apt install wget gpg
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
sudo apt update
sudo apt install code
```

Then apply the Home Manager profile, permit the user manager to live after
logout, and authenticate as `tu-le5`:

```
home-manager switch --flake ~/nix#tu-le5@work-linux
sudo loginctl enable-linger tu-le5
export VSCODE_CLI_USE_FILE_KEYCHAIN=1
code tunnel user login --provider github
chmod 600 ~/.vscode/cli/token.json
systemctl --user enable --now code-tunnel.service
```

Verify it and inspect failures with:

```
command -v code
systemctl --user status code-tunnel.service
loginctl show-user tu-le5 -p Linger
journalctl --user -u code-tunnel.service -f
```

If the token expires or is removed, rerun `code tunnel user login --provider
github`, then restart the unit with `systemctl --user restart
code-tunnel.service`. The current VS Code Linux installation instructions are
available at <https://code.visualstudio.com/docs/setup/linux>.

## 7. Offsite backup (optional)

`/data/tier1` and `/data/tier2` back up weekly (Sunday 03:00) to Google
Drive, keeping the latest 4 snapshots. First-time setup is interactive, once,
directly on the box (it already has a browser):

```
sudo rclone config
```

Create a remote named **`gdrive`** (type `drive`) and complete the Google
OAuth flow. See `hosts/homelab/nixos/backup.nix` for the schedule/retention knobs.

Trigger a backup on demand, outside the weekly schedule:

```
sudo systemctl start gdrive-backup.service
journalctl -u gdrive-backup -f   # follow progress
```

## 8. Recovering data from a backup

After a reinstall (steps 1–5) and redoing step 7's `sudo rclone config`,
restore the most recent snapshot — or a specific dated one — with:

```
sudo systemctl start gdrive-restore@latest.service
# or: sudo systemctl start gdrive-restore@20260709.service
journalctl -u 'gdrive-restore@*' -e
```

## Work laptop (Ubuntu)

Standalone home-manager (no NixOS): nix is only a package manager + dotfile
manager here. PaperWM, WezTerm, and all CLI tools come from nix; GNOME/GDM
itself stays as Ubuntu's, with PaperWM linked into the user extension dir.

1. Install nix (e.g. the Determinate Systems installer) on the laptop.
2. Clone this repo to `~/nix`.
3. Move Ubuntu's stock `~/.bashrc` out of the way. Home Manager now owns that
   file (it manages bash so `zoxide` can hook into it), and it will refuse to
   activate over an unclaimed file:

   ```
   mv ~/.bashrc ~/.bashrc.backup
   ```

4. Apply:

   ```
   home-manager switch --flake ~/nix#tu-le5@work-linux
   ```

   The profile includes the GKE authentication plugin. Authenticate the Google
   Cloud CLI when needed:

   ```
   gcloud auth login
   ```

   This stores credentials under `~/.config/gcloud`; they are imperative
   user state and must be re-created after a reinstall.

   Verify GKE access after fetching a cluster kubeconfig:

   ```
   gke-gcloud-auth-plugin --version
   kubectl cluster-info
   ```

5. Make Ubuntu's graphics drivers available to Nix GUI apps. The switch output
   prints a command like the following whenever this needs installing or
   refreshing; run that exact command with sudo:

   ```
   sudo /nix/store/<hash>-non-nixos-gpu/bin/non-nixos-gpu-setup
   ```

   It installs a small tmpfiles rule that recreates `/run/opengl-driver` at
   boot. This is required once after a fresh Ubuntu install and again only
   when a later `home-manager switch` reports that the GPU drivers need an
   update.

6. If this laptop previously used the Mango compositor, drop its GDM session
   entry (one-time cleanup; the flake no longer manages it):

   ```
   sudo rm -f /usr/share/wayland-sessions/mango.desktop
   ```

7. Log out and back in. GNOME Shell only picks up a newly installed extension
   on a fresh session, so PaperWM's tiling appears after the next login.
   Confirm with:

   ```
   gnome-extensions list --enabled | grep paperwm
   ```

## Desktop profile

PaperWM and WezTerm are separate shared capabilities under `modules/home/`,
selected explicitly by each host. PaperWM gives GNOME scrollable tiling; the
shortcuts are set in `modules/home/gnome-keys.nix` (Mango's old keys: Alt+arrows
focus, Super+Shift+arrows move, Alt+q close, Ctrl/Alt+1..9 workspaces).

NixOS plumbing is one `modules/nixos/gnome.nix`: GDM, audio, graphics,
Bluetooth, fonts, UPower, the GNOME session, and PaperWM. PaperWM has no
nixpkgs package — the `paperwm` flake input builds it, and the system profile
puts it where GNOME Shell looks for extensions.
`hosts/homelab/nixos/gnome-policy.nix` adds the server's no-sleep and
minimal-GNOME policy.

On the Ubuntu laptop `modules/home/gnome.nix` links the same extension into
`~/.local/share/gnome-shell/extensions/`, because GDM starts GNOME outside
the Nix profile and `XDG_DATA_DIRS` can't be relied on there.

Shell-wise, bash is the login shell and GNOME Terminal's shell on both
machines; `xonsh` is WezTerm's `default_prog` only. `zoxide` gives both `z`
and `zi` (with `fzf` for the interactive picker) without replacing `cd`.
Note PaperWM's upstream `shell-version` is 45–50, matching the GNOME Shell 50
that homelab's pinned nixpkgs ships; past that, switch the input to a versioned
upstream branch.
