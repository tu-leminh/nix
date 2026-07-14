# GNOME + Sway; GDM offers both at login. PipeWire audio.
{ pkgs, lib, ... }:
{
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  # Server box: never auto-sleep/suspend, even at the GDM greeter or on idle.
  services.displayManager.gdm.autoSuspend = false;
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Disable GNOME's session idle/suspend for all users via a dconf profile.
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

  # Minimal GNOME footprint: this is a server that occasionally gets a
  # desktop session, not a daily-driver laptop. Drop the background
  # services/apps that only earn their keep on a personal machine — file
  # indexing, cloud account sync, LAN file/media sharing, location services.
  # core-apps also pulls nautilus/gnome-software/maps/music/weather/
  # contacts/totem etc.; if you want any of those back (e.g. a GUI file
  # manager), add the package directly rather than re-enabling the whole set.
  services.gnome.tinysparql.enable = false;
  services.gnome.localsearch.enable = false;
  services.gnome.core-apps.enable = false;
  services.gnome.gnome-online-accounts.enable = false;
  services.gnome.evolution-data-server.enable = lib.mkForce false;
  services.gnome.gnome-user-share.enable = false;
  services.gnome.rygel.enable = false;
  services.geoclue2.enable = false;

  hardware.graphics.enable = true;

  # Bluetooth stack (needs the Intel adapter firmware from base.nix).
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  fonts.packages = with pkgs; [ noto-fonts noto-fonts-color-emoji dejavu_fonts ];

  # Sway UI toolkit only. User apps + dev tools live in ./apps.nix.
  environment.systemPackages = with pkgs; [ foot wofi waybar ];
}
