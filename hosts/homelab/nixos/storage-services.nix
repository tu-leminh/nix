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
  # changing the options below (v5 = EC default, only tier3 excepted, no SSD pins).
  systemd.services.bcachefs-tiering = {
    description = "Per-directory bcachefs redundancy";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/bcachefs-tiering-v5.done";
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
      # /var and /nix were pinned to the SSDs (foreground_target=ssd); that
      # pin is removed so they follow the pool default (2 replicas + EC, any
      # device). Watch k3s's SQLite datastore and containerd I/O on the slower
      # devices - if it stalls, re-pin /var to ssd and bump the stamp.
      bcachefs set-file-option --remove-all /var
      bcachefs set-file-option --remove-all /nix
      touch /var/lib/bcachefs-tiering-v5.done
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
