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
  github:nix-community/disko/latest -- --mode disko /tmp/nix/hosts/homelab/disk-config.nix
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
