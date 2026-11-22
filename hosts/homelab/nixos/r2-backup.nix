# Weekly offsite backup of /data/tier1 + /data/tier2 to Cloudflare R2, kept
# strictly inside the free tier (nix#21). R2 bills overage to the card on file
# with no hard cap of its own, so the guards live here:
#   - storage: one archive per run, at most `keep` kept, and the bucket total
#     must stay <= `hardCap` (below the 10 GB free tier) before AND after the
#     upload, or the run fails without uploading / removes what it uploaded;
#   - Class A ops (writes and lists, 1M/month free): one object per run in
#     large multipart chunks, a few lists, and a monthly local budget
#     (`classABudget`) that stops the run before it could get near the limit;
#     deletes are free on R2;
#   - Class B ops (reads, 10M/month free): the backup never reads objects back.
#
# One-time setup (imperative, like the Drive backup):
#   1. wrangler login; wrangler r2 bucket create homelab-backup
#      wrangler r2 bucket lifecycle add homelab-backup abort-mpu --abort-multipart-days 1
#      (abandoned multipart parts would otherwise count as storage)
#   2. Dashboard: R2 > Manage API tokens > Object Read & Write on that bucket;
#      `sudo rclone config` -> remote `r2`, type s3, provider Cloudflare.
#   3. age-keygen -o r2-backup.key; keep that file OFF this host (it is the
#      only way to decrypt; the archive holds Vaultwarden and the OpenBao seal
#      key), and put its public key in /root/.config/r2-backup/age-recipients.
#   4. Dashboard: Notifications > add a billing/usage alert as a last resort.
# Until 2 and 3 are done the units are skipped (ConditionPathExists).
{ pkgs, lib, ... }:
let
  remote = "r2:homelab-backup";
  rcloneConfig = "/root/.config/rclone/rclone.conf";
  recipients = "/root/.config/r2-backup/age-recipients";
  work = "/var/lib/r2-backup";
  keep = 2; # archives retained, including the new one
  hardCap = 9000000000; # bytes; free tier is 10 GB
  warnAt = 8000000000;
  classABudget = 50000; # per calendar month; free tier is 1,000,000
  chunk = 67108864; # 64 MiB multipart parts: ~16 Class A ops per GiB
  schedule = "Sun *-*-* 04:00:00";
in
{
  environment.systemPackages = [ pkgs.age ];

  systemd.services.r2-backup = {
    description = "Weekly offsite backup of /data/tier1 and /data/tier2 to Cloudflare R2";
    unitConfig.ConditionPathExists = [ rcloneConfig recipients ];
    path = with pkgs; [ rclone bcachefs-tools gnutar zstd age coreutils gnused ];
    environment = {
      RCLONE_CONFIG = rcloneConfig;
      # Skip rclone's CreateBucket probe: a Class A op on every write.
      RCLONE_S3_NO_CHECK_BUCKET = "true";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      name="homelab-$(date +%Y%m%d).tar.zst.age"
      mkdir -p ${work}
      rm -f ${work}/*.age

      # Local tally of the Class A operations this unit makes, per month.
      opsfile=${work}/class-a-$(date +%Y%m)
      used=$(cat "$opsfile" 2>/dev/null || echo 0)
      ops() { used=$((used + $1)); echo "$used" > "$opsfile"; }
      if [ "$used" -ge ${toString classABudget} ]; then
        echo "monthly Class A budget used up ($used ops); not uploading" >&2; exit 1
      fi

      # Archive read-only snapshots, not the live directories (consistent
      # SQLite/pebbledb state, see backup.nix).
      snapdir=/var/lib/r2-backup-snap
      cleanup_snaps() {
        for s in "$snapdir"/*; do
          if [ -e "$s" ]; then bcachefs subvolume delete "$s"; fi
        done
      }
      trap cleanup_snaps EXIT
      cleanup_snaps
      mkdir -p "$snapdir"
      bcachefs subvolume snapshot -r /data/tier1 "$snapdir/tier1"
      bcachefs subvolume snapshot -r /data/tier2 "$snapdir/tier2"
      tar -C "$snapdir" -cf - tier1 tier2 | zstd -q -T0 -10 | age -R ${recipients} > "${work}/$name"
      cleanup_snaps
      size=$(stat -c %s "${work}/$name")
      sha=$(sha256sum "${work}/$name" | cut -d' ' -f1)
      echo "archive $name: $size bytes"
      if [ "$size" -gt ${toString hardCap} ]; then
        echo "archive alone exceeds the cap; not uploading" >&2; exit 1
      fi

      # One LIST (Class A). An archive counts only with its .ok marker, which
      # is written last; anything else is a failed run and is deleted (free).
      ops 1
      listing=$(rclone lsf --files-only --format sp --separator ' ' "${remote}/")
      good=""; total=0
      for f in $(echo "$listing" | cut -d' ' -f2 | grep '\.age$' | sort); do
        if echo "$listing" | grep -qx "[0-9]* $f.ok"; then good="$good $f"; else rclone deletefile "${remote}/$f"; fi
      done
      for m in $(echo "$listing" | cut -d' ' -f2 | grep '\.ok$'); do
        echo "$good" | grep -qw "''${m%.ok}" || rclone deletefile "${remote}/$m"
      done
      # Keep keep-1 old archives so that `keep` remain after this upload.
      n=$(printf '%s\n' $good | grep -c . || true)
      for f in $(printf '%s\n' $good | head -n $((n > ${toString (keep - 1)} ? n - ${toString (keep - 1)} : 0))); do
        rclone deletefile "${remote}/$f"; rclone deletefile "${remote}/$f.ok"
        good=$(echo "$good" | sed "s/ $f//")
      done
      for f in $good; do
        total=$((total + $(echo "$listing" | grep " $f$" | cut -d' ' -f1)))
      done
      if [ $((total + size)) -gt ${toString hardCap} ]; then
        echo "bucket would reach $((total + size)) bytes (> cap); not uploading" >&2; exit 1
      fi

      # Multipart upload: create + complete + one op per part.
      ops $(( (size + ${toString chunk} - 1) / ${toString chunk} + 2 ))
      rclone copyto --s3-chunk-size ${toString chunk} "${work}/$name" "${remote}/$name"
      ops 1
      echo "$sha $size" | rclone rcat "${remote}/$name.ok"
      rm -f "${work}/$name"

      # Re-check the real bucket total (one more LIST); undo if over the cap.
      ops 1
      now=$(rclone size --json "${remote}/" | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
      echo "bucket total: $now bytes; Class A this month: $used"
      if [ "$now" -gt ${toString hardCap} ]; then
        rclone deletefile "${remote}/$name.ok"; rclone deletefile "${remote}/$name"
        echo "bucket over the cap after upload; removed the new archive" >&2; exit 1
      fi
      if [ "$now" -gt ${toString warnAt} ]; then
        echo "WARNING: bucket at $now bytes, close to the free tier" >&2; exit 1
      fi
    '';
  };

  systemd.timers.r2-backup = {
    description = "Weekly timer for r2-backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = schedule;
      Persistent = true;
    };
  };

  # Manual restore: systemctl start r2-restore@<YYYYMMDD|latest>.service, with
  # the age identity copied to /root/.config/r2-backup/age-identity first.
  # Extracts over /data/tier1 and /data/tier2 (a download is a few Class B ops).
  systemd.services."r2-restore@" = {
    description = "Restore /data/tier1 and /data/tier2 from an R2 archive (%i = date or 'latest')";
    unitConfig.ConditionPathExists = [ rcloneConfig "/root/.config/r2-backup/age-identity" ];
    path = with pkgs; [ rclone gnutar zstd age coreutils ];
    environment = {
      RCLONE_CONFIG = rcloneConfig;
      SNAPSHOT = "%i";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      listing=$(rclone lsf --files-only "${remote}/")
      if [ "$SNAPSHOT" = latest ]; then
        name=$(echo "$listing" | grep '\.age\.ok$' | sort | tail -n 1 | sed 's/\.ok$//')
      else
        name="homelab-$SNAPSHOT.tar.zst.age"
        echo "$listing" | grep -qx "$name.ok" || name=""
      fi
      [ -n "$name" ] || { echo "no complete archive found" >&2; exit 1; }
      rclone cat "${remote}/$name" | age -d -i /root/.config/r2-backup/age-identity | zstd -dq | tar -C /data -xf -
      echo "restored $name"
    '';
  };
}
