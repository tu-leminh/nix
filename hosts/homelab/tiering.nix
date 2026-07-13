# First boot: set per-directory redundancy that differs from the pool default
# (replicas=2, no EC). bcachefs inherits these to newly written files.
{ pkgs, ... }:
{
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
}
