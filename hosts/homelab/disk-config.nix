# The 5-disk bcachefs pool layout (disko.devices only). Kept free of `pkgs`
# and other NixOS options so it can be fed to the disko CLI standalone
# (`disko --mode disko .../disk-config.nix`) — that path just `import`s this
# file and calls it without `pkgs`. Runtime storage config (per-directory
# tiering, SMART) lives in ./storage.nix, which imports this and is pulled into
# the host via nixos-install --flake. Disk tiers: ssd = foreground+promote,
# hdd = background, nvme = plain member. ESP (/boot) on the NVMe. Pool default
# replicas=2, no EC (covers / and tier2); per-directory overrides in storage.nix.
#
# A bare attrset, not a `{ ... }:` module function: the disko CLI does
# `import <file>` and only applies arguments if the result is a function, so a
# plain attrset can never trip a "called without required argument 'pkgs'"
# error. NixOS `imports` accepts a config-only attrset like this too.
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
              priority = 1;
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            # Raw disk swap, layered under zram (see ./swap.nix) as overflow
            # capacity rather than a replacement for it. Explicit priority:
            # disko falls back to alphabetical partition order ("pool" before
            # "swap"), and pool's size="100%" would otherwise claim all
            # remaining space before this partition gets created.
            swap = {
              priority = 2;
              size = "32G";
              content = {
                type = "swap";
                priority = 10; # lower than zram's, so zram is exhausted first
              };
            };
            pool = {
              priority = 3;
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
      # Never add --casefold: it breaks overlayfs, which is unreliable on
      # bcachefs anyway (k3s uses --snapshotter=native to avoid it, see
      # ./k3s/default.nix). Off by default; recheck on bcachefs/kernel updates.
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
