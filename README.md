# nix

Bcachefs installer ISO + a tiered 5-disk NixOS home-lab host (K3s + Argo CD),
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

Boot the USB first. This **erases all 5 disks** (wipes any existing OS):

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

## 6. Remote access (optional)

The box also runs a VS Code tunnel for remote access. First-time login is
interactive, once:

```
export VSCODE_CLI_USE_FILE_KEYCHAIN=1
code tunnel user login --provider github
code tunnel --accept-server-license-terms
```

See `hosts/homelab/nixos/vscode-tunnel.nix` for why `VSCODE_CLI_USE_FILE_KEYCHAIN`
matters on a headless boot.

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
manager here. Mango, Noctalia, WezTerm, and all CLI tools come from nix;
GNOME/GDM stays as the login manager and Mango is picked from it.

1. Install nix (e.g. the Determinate Systems installer) on the laptop.
2. Clone this repo to `~/nix`.
3. Apply:

   ```
   home-manager switch --flake ~/nix#tu-le5@work-linux
   ```

4. Register Mango with GDM. This is needed once after a fresh Ubuntu install:

   ```
   sudo install -Dm644 ~/.local/share/wayland-sessions/mango.desktop \
     /usr/share/wayland-sessions/mango.desktop
   ```

   GDM reads its session list before login, so it does not discover the
   Home Manager-managed user entry. The installed file uses the stable
   `~/.nix-profile/bin/mango` path, so later `home-manager switch` runs keep
   the session working. Log out and choose "Mango" from GDM's session menu.

   Mango, Noctalia, and WezTerm are wrapped with NixGL on this Intel Ubuntu
   laptop, so they receive a compatible Mesa/EGL runtime. No extra graphics
   setup is required after `home-manager switch`.

## Desktop profile

Mango, Noctalia, and WezTerm are separate shared capabilities under
`modules/home/`, selected explicitly by each host. Mango starts Noctalia once; Super+Space opens its launcher,
Super+S opens the control center, Super+Comma opens Settings,
Super+Shift+S starts a region screenshot, and Super+L locks the session.

NixOS plumbing is split by capability: `modules/nixos/graphical.nix` supplies
GDM, audio, graphics, Bluetooth, fonts, and UPower; `gnome.nix` and `mango.nix`
enable their respective sessions. `hosts/homelab/nixos/gnome-policy.nix` adds
the server's no-sleep and minimal-GNOME policy.

The bar config (floating, CPU/mem, clock, media, etc.) is managed declaratively
in `modules/home/noctalia.nix`. Noctalia Settings writes GUI overrides to
`~/.local/state/noctalia/settings.toml`, which wins over the managed config and
survives a reinstall only if copied by hand.
