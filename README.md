# nix

Bcachefs installer ISO + a tiered 5-disk NixOS home-lab host (K3s + Argo CD).
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
  github:nix-community/disko/latest -- --mode disko /tmp/nix/hosts/homelab/storage.nix
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
kubectl -n core get applications
```

## 6. Remote access (optional)

The box also runs a VS Code tunnel for remote access. First-time login is
interactive, once:

```
export VSCODE_CLI_USE_FILE_KEYCHAIN=1
code tunnel user login --provider github
code tunnel --accept-server-license-terms
```

See `hosts/homelab/vscode-tunnel.nix` for why `VSCODE_CLI_USE_FILE_KEYCHAIN`
matters on a headless boot.

## 7. Offsite backup (optional)

`/data/tier1` and `/data/tier2` back up weekly (Sunday 03:00) to Google
Drive, keeping the latest 4 snapshots. First-time setup is interactive, once,
directly on the box (it already has a browser):

```
sudo rclone config
```

Create a remote named **`gdrive`** (type `drive`) and complete the Google
OAuth flow. See `hosts/homelab/backup.nix` for the schedule/retention knobs.

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
