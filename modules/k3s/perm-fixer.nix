# kubelet creates new hostPath directories as root:root on first mount,
# but every app in argohome runs as UID/GID 1000 (see argohome's README
# "Security Context & UID Rules"). This used to be a k8s CronJob, but that
# meant giving a pod a root securityContext and a full /data hostPath mount
# just to chown two directories — a host filesystem concern, not an app
# one — so it runs here instead.
#
# Event-driven rather than polled: a systemd .path unit watches the two
# directories via inotify and reruns the fixer within seconds of a new
# app's PV creating a fresh root-owned subdirectory, instead of waiting
# for the next tick of a timer.
{ pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "Z /data/tier2/configs - 1000 1000 -"
    "Z /data/tier3/shared - 1000 1000 -"
  ];

  systemd.services.perm-fixer = {
    description = "Fix ownership of k3s app config/shared data dirs";
    after = [ "local-fs.target" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.coreutils ];
    script = ''
      set -eu
      ${pkgs.systemd}/bin/systemd-tmpfiles --create --prefix=/data/tier2/configs --prefix=/data/tier3/shared

      # Secure Traefik ACME storage (must be 600) — tmpfiles Z above only
      # covers ownership/dir mode, not this per-file mode.
      for f in /data/tier2/configs/traefik/*.json; do
        [ -e "$f" ] || continue
        chown 1000:1000 "$f"
        chmod 600 "$f"
      done
    '';
  };

  systemd.paths.perm-fixer = {
    description = "Watch k3s app data dirs for newly created root-owned subdirs";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = [ "/data/tier2/configs" "/data/tier3/shared" ];
    };
  };
}
