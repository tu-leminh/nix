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
      unshare -m ${pkgs.runtimeShell} -euc '
        mount -o remount,bind,rw /nix/store
        bcachefs set-file-option --remove-all /nix /nix/store
      '
      touch /var/lib/bcachefs-tiering-v8.done
    '';
  };

  # SMART monitoring for the physical disks. Covers physical device health
  # only (reallocated/pending sectors, temperature) — it knows nothing about
  # the bcachefs layer itself (replica degradation, checksum errors, scrub
  # status). Check `bcachefs fs usage -h /` periodically for that.
  # Self-tests: short daily at 02:00, long (1.5-3h on the HDDs) Saturdays at
  # 03:00. The health flag alone stays PASSED until a drive is nearly dead.
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.autodetected = "-a -s (S/../.././02|L/../../6/03)";
  };
  environment.systemPackages = [ pkgs.smartmontools ];

  # Self-test results as Prometheus metrics (./smart-selftest.jq), for
  # node-exporter's textfile collector; smartctl_exporter doesn't read the
  # self-test log. Shown per disk on Homepage (argohome).
  systemd.services.smart-selftest-metrics = {
    description = "Export SMART self-test results for node-exporter";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "prometheus-node-exporter-text";
    };
    path = [ pkgs.smartmontools pkgs.jq pkgs.gawk ];
    script = ''
      set -eu
      dir=/var/lib/prometheus-node-exporter-text
      tmp=$(mktemp "$dir/.smart_selftest.XXXXXX")
      # smartctl's exit status is a bitmask of disk conditions, not failure.
      for dev in $(smartctl --scan | awk '{print $1}'); do
        smartctl -j -a -n standby "$dev" || true
      done | jq -rs -f ${./smart-selftest.jq} > "$tmp"
      chmod 644 "$tmp"
      mv "$tmp" "$dir/smart_selftest.prom"
    '';
  };
  systemd.timers.smart-selftest-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
    };
  };
}
