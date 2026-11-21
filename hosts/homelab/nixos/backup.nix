# Weekly offsite backup of /data/tier1 + /data/tier2 to Google Drive via rclone.
#
# First-time setup (interactive, once) — run directly on this machine (it has
# GNOME + a browser already, e.g. google-chrome), no separate machine or file
# copy needed:
#   sudo rclone config
# Create a remote named `gdrive` (type `drive`), complete the Google OAuth
# flow in the browser. This writes /root/.config/rclone/rclone.conf, which is
# imperative state (like the argohome deploy key and the VS Code tunnel
# token) — not in the flake, so re-do this once after a reinstall.
{ pkgs, lib, ... }:
let
  drive = "gdrive:"; # whole remote; `rclone cleanup` empties its trash
  remote = "${drive}backup";
  rcloneConfig = "/root/.config/rclone/rclone.conf";
  dirs = [ "/data/tier1" "/data/tier2" ]; # full source paths, mirrored as-is on Drive
  keep = 4; # snapshots to retain (current + 3 previous)
  schedule = "Sun *-*-* 03:00:00"; # weekly, Sunday 03:00
in
{
  environment.systemPackages = [ pkgs.rclone ]; # for the `rclone config` step above

  # Runs weekly via the timer below, but being a plain oneshot service it can
  # also be triggered on demand, same as any systemd service:
  #   sudo systemctl start gdrive-backup.service
  # Follow progress with: journalctl -u gdrive-backup -f
  systemd.services.gdrive-backup = {
    description = "Weekly offsite backup of /data/tier1 and /data/tier2 to Google Drive";
    unitConfig.ConditionPathExists = rcloneConfig;
    path = [ pkgs.rclone pkgs.bcachefs-tools ];
    environment = {
      RCLONE_CONFIG = rcloneConfig;
      # Drive's trash counts against the quota, so deletes (purge, overwritten
      # files) must bypass it or old snapshots never free any space.
      RCLONE_DRIVE_USE_TRASH = "false";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      date=$(date +%Y%m%d)

      # Empty the Drive trash first: it counts against the quota, and this
      # Drive is dedicated to these backups, so nothing in it is worth keeping
      # (nix#11). Like the prune, a failure here must not stop the copy.
      rclone cleanup "${drive}" || echo "trash cleanup failed, continuing" >&2

      # A dated folder only counts as a snapshot once its COMPLETE marker exists
      # (written last, below), so a failed or interrupted run is never mistaken
      # for a good backup by the prune or by gdrive-restore@latest (nix#17).
      complete() { rclone lsf --files-only "${remote}/$1" 2>/dev/null | grep -qx COMPLETE; }

      # Prune BEFORE copying, and don't let a prune error stop the copy: when
      # the quota is full the copy fails, and pruning only after it meant old
      # snapshots were never removed (nix#9). Incomplete folders (failed runs)
      # are always removed; of the complete ones keep one fewer than `keep`, so
      # that with today's snapshot exactly `keep` remain. Folder names sort
      # chronologically as plain strings (YYYYMMDD/).
      {
        good=""
        for d in $(rclone lsf --dirs-only "${remote}/" | sort); do
          if complete "$d"; then good="$good $d"; else rclone purge "${remote}/$d"; fi
        done
        for d in $(printf '%s\n' $good | head -n -${toString (keep - 1)}); do
          rclone purge "${remote}/$d"
        done
      } || echo "prune failed, continuing" >&2

      # Copy from read-only bcachefs snapshots, not the live directories: a
      # run takes hours, and live SQLite/pebbledb files (Vaultwarden, OpenBao)
      # copied mid-write can't be restored. Snapshots are copy-on-write, so
      # they cost almost nothing, and they are always removed again.
      snapdir=/var/lib/backup-snap
      cleanup_snaps() {
        for s in "$snapdir"/*; do
          if [ -e "$s" ]; then bcachefs subvolume delete "$s"; fi
        done
      }
      trap cleanup_snaps EXIT
      cleanup_snaps # leftovers from an interrupted run
      mkdir -p "$snapdir"

      # Each source path is mirrored as-is under the dated snapshot, e.g.
      # /data/tier1 -> gdrive:backup/$date/data/tier1 (no name-collapsing),
      # so the Drive layout is unambiguous and restore is a straight mirror.
      # A failed copy still lets the others run, then fails the unit.
      status=0
      ${lib.concatMapStringsSep "\n" (d: ''
        snap="$snapdir/${baseNameOf d}"
        if bcachefs subvolume snapshot -r ${d} "$snap"; then
          rclone copy -v "$snap" "${remote}/$date${d}" || status=1
        else
          status=1
        fi
      '') dirs}

      if [ $status -eq 0 ]; then
        date -Is | rclone rcat "${remote}/$date/COMPLETE"
      fi
      exit $status
    '';
  };

  systemd.timers.gdrive-backup = {
    description = "Weekly timer for gdrive-backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = schedule;
      Persistent = true; # catch up if the box was off at the scheduled time
    };
  };

  # Manually triggered restore, run as `systemctl start gdrive-restore@<snapshot>.service`
  # where <snapshot> is a date like 20260709, or the literal `latest`.
  # Systemd expands the %i instance specifier in Environment= (not inside the
  # script body), hence the SNAPSHOT env var indirection below.
  systemd.services."gdrive-restore@" = {
    description = "Restore /data/tier1 and /data/tier2 from a Google Drive snapshot (%i = date or 'latest')";
    unitConfig.ConditionPathExists = rcloneConfig;
    path = [ pkgs.rclone ];
    environment = {
      RCLONE_CONFIG = rcloneConfig;
      SNAPSHOT = "%i";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      snapshot=$SNAPSHOT
      if [ "$snapshot" = "latest" ]; then
        # Newest folder with a COMPLETE marker; never a partial run.
        snapshot=""
        for d in $(rclone lsf --dirs-only "${remote}/" | sort -r); do
          if rclone lsf --files-only "${remote}/$d" | grep -qx COMPLETE; then snapshot=''${d%/}; break; fi
        done
        [ -n "$snapshot" ] || { echo "no complete snapshot found" >&2; exit 1; }
      fi

      ${lib.concatMapStringsSep "\n" (d: ''
        rclone copy -v "${remote}/$snapshot${d}" ${d}
      '') dirs}
    '';
  };
}
