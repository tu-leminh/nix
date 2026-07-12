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

  hardware.graphics.enable = true;

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
