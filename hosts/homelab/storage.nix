# Runtime storage config for the bcachefs pool: first-boot per-directory
# tiering and SMART monitoring. The pool layout itself (disko.devices) lives in
# ./disk-config.nix — a `pkgs`-free file so the disko CLI can consume it
# standalone; this module can't be handed to disko directly because it needs
# `pkgs` and sets NixOS-only options. See ./disk-config.nix for tier details.
{ pkgs, ... }:
{
  imports = [ ./disk-config.nix ];

  # First boot: set per-directory redundancy that differs from the pool
  # default (replicas=2, no EC). bcachefs inherits these to newly written files.
  systemd.services.bcachefs-tiering = {
    description = "Per-directory bcachefs redundancy";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/bcachefs-tiering.done";
    path = [ pkgs.bcachefs-tools ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      bcachefs set-file-option --data_replicas=3 --erasure_code=0 /data/tier1
      bcachefs set-file-option --data_replicas=1 --erasure_code=0 /data/tier3
      touch /var/lib/bcachefs-tiering.done
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
