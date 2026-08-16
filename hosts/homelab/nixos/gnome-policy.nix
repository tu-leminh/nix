# Server-only GNOME policy; the shared Mango + Noctalia profile stays in user/.
{ lib, ... }:
{
  services.displayManager.gdm.autoSuspend = false;
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  programs.dconf.profiles.user.databases = [{
    settings = {
      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-battery-type = "nothing";
        idle-dim = false;
      };
      "org/gnome/desktop/session".idle-delay = lib.gvariant.mkUint32 0;
    };
  }];

  services.gnome.tinysparql.enable = false;
  services.gnome.localsearch.enable = false;
  services.gnome.core-apps.enable = false;
  services.gnome.gnome-online-accounts.enable = false;
  services.gnome.evolution-data-server.enable = lib.mkForce false;
  services.gnome.gnome-user-share.enable = false;
  services.gnome.rygel.enable = false;
  services.geoclue2.enable = false;
}
