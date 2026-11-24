# Runtime storage config for the bcachefs pool: first-boot per-directory
# tiering and SMART monitoring. Split from ./storage.nix because these need
# `pkgs` and set NixOS-only options, which would break the standalone disko CLI
# run (`disko --mode disko .../storage.nix`). ./default.nix imports both.
{ pkgs, ... }:
{
  # Pool default is replicas=2 with erasure coding on (set below; the format
  # args in ./storage.nix can't change an existing pool). Per-directory options
  # override it: tier1 keeps 3 replicas on the SSDs, tier3 is 1 replica, no EC.
  # bcachefs inherits these to newly written files and reconciles existing ones
  # in the background. The stamp is versioned: bump it to re-run this after
  # changing the options below (v6 = small hot dirs pinned to the SSDs).
  systemd.services.bcachefs-tiering = {
    description = "Per-directory bcachefs redundancy";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/bcachefs-tiering-v6.done";
    path = [ pkgs.bcachefs-tools ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      # Persisted in the superblock; any member device works as the handle.
      bcachefs set-fs-option --erasure_code=1 /dev/disk/by-id/ata-WDC_WDS500G2B0A_2013BV468107-part1
      bcachefs set-file-option --data_replicas=2 --erasure_code=1 /data/tier2
      bcachefs set-file-option --data_replicas=1 --erasure_code=0 /data/tier3

      # Small, write-heavy dirs live on the SSDs (~45G of ~2.3T): k3s's
      # SQLite datastore stalled on the HDDs and crashed k3s (#4), and the app
      # SQLite DBs and vmsingle see the same small synchronous writes. Unlike
      # the old whole-/var+/nix pin (which filled ssd0), this set is small.
      # background_target keeps data there if a write ever spills to an HDD.
      # EC is off: with background_target=ssd a stripe could only use the
      # same-bucket-size SSDs (nvme0, ssd0: 2 of the 3 needed), so reconcile
      # would park the EC work as pending forever.
      ssd="--foreground_target=ssd --background_target=ssd --promote_target=ssd --erasure_code=0"
      bcachefs set-file-option --data_replicas=3 $ssd /data/tier1 # one copy per SSD
      bcachefs set-file-option --data_replicas=2 $ssd /var
      bcachefs set-file-option --data_replicas=2 $ssd /data/tier2/configs
      bcachefs set-file-option --data_replicas=1 $ssd /data/tier3/monitoring
      # The store is 64G and read-mostly: cache reads on the SSDs only.
      bcachefs set-file-option --remove-all /nix
      bcachefs set-file-option --promote_target=ssd /nix
      touch /var/lib/bcachefs-tiering-v6.done
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
