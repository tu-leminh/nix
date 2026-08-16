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
  remote = "gdrive:backup";
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
    path = [ pkgs.rclone ];
    environment.RCLONE_CONFIG = rcloneConfig;
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      date=$(date +%Y%m%d)

      # Each source path is mirrored as-is under the dated snapshot, e.g.
      # /data/tier1 -> gdrive:backup/$date/data/tier1 (no name-collapsing),
      # so the Drive layout is unambiguous and restore is a straight mirror.
      ${lib.concatMapStringsSep "\n" (d: ''
        rclone copy -v ${d} "${remote}/$date${d}"
      '') dirs}

      # Snapshot dirs sort chronologically as plain strings (YYYYMMDD);
      # `head -n -N` (GNU coreutils) prints all but the newest N.
      rclone lsf --dirs-only "${remote}/" | sort | head -n -${toString keep} | while read -r old; do
        rclone purge "${remote}/$old"
      done
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
        snapshot=$(rclone lsf --dirs-only "${remote}/" | sort | tail -n1)
      fi

      ${lib.concatMapStringsSep "\n" (d: ''
        rclone copy -v "${remote}/$snapshot${d}" ${d}
      '') dirs}
    '';
  };
}
