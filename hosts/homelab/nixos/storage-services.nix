# Runtime storage config for the bcachefs pool: first-boot per-directory
# tiering and SMART monitoring. Split from ./storage.nix because these need
# `pkgs` and set NixOS-only options, which would break the standalone disko CLI
# run (`disko --mode disko .../storage.nix`). ./default.nix imports both.
{ pkgs, ... }:
{
  # Pool default is replicas=2 with erasure coding on (set below; the format
  # args in ./storage.nix can't change an existing pool), metadata on the SSDs.
  # Only two per-directory exceptions: tier1 keeps 3 replicas (3+2 with EC),
  # tier3 is 1 replica, no EC. No data is pinned to the SSDs. bcachefs
  # inherits these to newly written files and reconciles existing ones in the
  # background. The stamp is versioned: bump it to re-run this after changing
  # the options below (v8 = only the tier1/tier3 exceptions, all others cleared).
  systemd.services.bcachefs-tiering = {
    description = "Per-directory bcachefs redundancy";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/bcachefs-tiering-v8.done";
    path = [
      pkgs.bcachefs-tools
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      # Persisted in the superblock; any member device works as the handle.
      bcachefs set-fs-option --erasure_code=1 /dev/disk/by-id/ata-WDC_WDS500G2B0A_2013BV468107-part1
      bcachefs set-file-option --remove-all --data_replicas=3 /data/tier1
      bcachefs set-file-option --remove-all --data_replicas=1 --erasure_code=0 /data/tier3

      # Clear the overrides earlier layouts left (SSD pins, read cache, manual
      # ones). --remove-all re-inherits down the tree but stops at children
      # with their own options, so each one is named.
      bcachefs set-file-option --remove-all /var /var/lib/rancher /var/lib/kubelet \
        /data/tier2 /data/tier2/configs /data/tier3/monitoring
      # /nix/store is a read-only bind mount, where set-file-option fails per
      # file yet exits 0; remount it rw in a private namespace, as nix-daemon does.
      unshare -m sh -euc '
        mount -o remount,bind,rw /nix/store
        bcachefs set-file-option --remove-all /nix /nix/store
      '
      touch /var/lib/bcachefs-tiering-v8.done
    '';
  };

  # SMART monitoring for the 5 physical disks. Covers physical device health
  # only (reallocated/pending sectors, temperature) — it knows nothing about
  # the bcachefs layer itself (replica degradation, checksum errors, scrub
  # status). Check `bcachefs fs usage -h /` periodically for that.
  services.smartd = {
    enable = true;
    autodetect = true;
  };
  environment.systemPackages = [ pkgs.smartmontools ];
}
