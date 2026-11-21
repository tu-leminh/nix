# Runtime storage config for the bcachefs pool: first-boot per-directory
# tiering and SMART monitoring. Split from ./storage.nix because these need
# `pkgs` and set NixOS-only options, which would break the standalone disko CLI
# run (`disko --mode disko .../storage.nix`). ./default.nix imports both.
{ pkgs, ... }:
{
  # Pool default is replicas=2 with erasure coding on (set below; the format
  # args in ./storage.nix can't change an existing pool). Per-directory options
  # override it: tier1 keeps 3 replicas (3+2 with EC), tier3 is 1 replica, no EC.
  # bcachefs inherits these to newly written files and reconciles existing ones
  # in the background. The stamp is versioned: bump it to re-run this after
  # changing the options below (v4 = EC default, only tier3 excepted).
  systemd.services.bcachefs-tiering = {
    description = "Per-directory bcachefs redundancy";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/bcachefs-tiering-v4.done";
    path = [ pkgs.bcachefs-tools ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      # Persisted in the superblock; any member device works as the handle.
      bcachefs set-fs-option --erasure_code=1 /dev/disk/by-id/ata-WDC_WDS500G2B0A_2013BV468107-part1
      bcachefs set-file-option --data_replicas=3 --erasure_code=1 /data/tier1
      bcachefs set-file-option --data_replicas=2 --erasure_code=1 /data/tier2
      bcachefs set-file-option --data_replicas=1 --erasure_code=0 /data/tier3
      # nix store: same as /var - pin to SSDs so app and update reads never hit
      # the slow HDDs (1x replicas, no target would spread it across all disks).
      # /var: pin replicas=2 + SSDs explicitly (pool default would spread it
      # across the slow HDDs). Inherited by everything below it - k3s's
      # embedded SQLite datastore and containerd's overlayfs layer extraction
      # (containerd is embedded in k3s, no separate top-level dir), journald,
      # /var/lib/homelab - small, latency-sensitive random I/O, so the old
      # per-dir k3s/kubelet lines are covered by this one. /var is a plain dir
      # in the root subvolume (no var subvolume in the layout), so this sets
      # inode options on the dir itself.
      bcachefs set-file-option --data_replicas=2 --foreground_target=ssd --erasure_code=1 /var
      bcachefs set-file-option --data_replicas=2 --foreground_target=ssd --erasure_code=1 /nix
      touch /var/lib/bcachefs-tiering-v4.done
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
