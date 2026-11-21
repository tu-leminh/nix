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

  # Daily local snapshot of k3s's server state into tier1, so the weekly Drive
  # backup above carries it. /var is not backed up, and losing it means a new
  # cluster CA and every Tailscale device re-registering. k3s runs on SQLite
  # (kine) here, so the datastore is copied with sqlite's online backup API
  # rather than a file copy, which could catch a half-written WAL.
  # The archive holds the cluster CA keys and token in plaintext, so it has
  # the same Drive-account trade-off as the OpenBao bootstrap files.
  # Restore: stop k3s, extract over /var/lib/rancher/k3s/server, start k3s.
  systemd.services.k3s-state-backup = {
    description = "Snapshot k3s server state (SQLite datastore, CA, token) into tier1";
    path = with pkgs; [ sqlite zstd gnutar coreutils findutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      umask 077
      server=/var/lib/rancher/k3s/server
      dest=/data/tier1/k3s-backup
      stamp=$(date +%Y%m%d-%H%M%S)
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT

      mkdir -p "$dest" "$work/server/db"
      sqlite3 "$server/db/state.db" ".backup '$work/server/db/state.db'"
      [ "$(sqlite3 "$work/server/db/state.db" 'pragma integrity_check')" = ok ]
      cp -a "$server/tls" "$server/cred" "$server/token" "$work/server/"

      tar -C "$work" -cf - server | zstd -q -o "$dest/k3s-server-$stamp.tar.zst.tmp"
      mv "$dest/k3s-server-$stamp.tar.zst.tmp" "$dest/k3s-server-$stamp.tar.zst"

      # Keep the newest 7; names sort chronologically.
      ls -1 "$dest"/k3s-server-*.tar.zst | head -n -7 | xargs -r rm -f
    '';
  };

  systemd.timers.k3s-state-backup = {
    description = "Daily timer for k3s-state-backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:30:00"; # before the Sunday 03:00 Drive backup
      Persistent = true;
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
