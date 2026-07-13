# One bcachefs pool over all 5 disks. Tiers: ssd = foreground+promote,
# hdd = background, nvme = plain member. ESP (/boot) on the NVMe.
# Pool default replicas=2, no EC (covers / and tier2); overrides in ./tiering.nix.
{ ... }:
let
  # Whole-disk bcachefs pool member on `dev`, tagged `label`.
  poolMember = dev: label: {
    type = "disk";
    device = dev;
    content = {
      type = "gpt";
      partitions.pool = {
        size = "100%";
        content = { type = "bcachefs"; filesystem = "pool"; inherit label; };
      };
    };
  };
in
{
  imports = [ ./tiering.nix ];

  disko.devices = {
    disk = {
      # NVMe: ESP (/boot) + pool member.
      nvme = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-CT2000P3PSSD8_2350E88850A3";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            pool = {
              size = "100%";
              content = { type = "bcachefs"; filesystem = "pool"; label = "nvme.nvme0"; };
            };
          };
        };
      };

      ssd = poolMember "/dev/disk/by-id/ata-WDC_WDS500G2B0A_2013BV468107" "ssd.ssd0";
      hdd0 = poolMember "/dev/disk/by-id/ata-HGST_HTS721010A9E630_JR1000D318DL7E" "hdd.hdd0";
      hdd1 = poolMember "/dev/disk/by-id/ata-WDC_WD5000LPVX-80V0TT0_WD-WX81AB48A024" "hdd.hdd1";
      hdd2 = poolMember "/dev/disk/by-id/ata-ST2000LM007-1R8174_WDZG9GQS" "hdd.hdd2";
    };

    bcachefs_filesystems.pool = {
      type = "bcachefs_filesystem";
      # Never add --casefold: it breaks overlayfs (k3s/containerd). Off by
      # default; recheck on bcachefs/kernel updates.
      extraFormatArgs = [
        "--foreground_target=ssd"
        "--promote_target=ssd"
        "--background_target=hdd"
        "--metadata_target=ssd"
        "--replicas=2"
      ];
      subvolumes = {
        "root".mountpoint = "/";
        "data/tier1".mountpoint = "/data/tier1";
        "data/tier2".mountpoint = "/data/tier2";
        "data/tier3".mountpoint = "/data/tier3";
      };
    };
  };
}
