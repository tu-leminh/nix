# The graphical session: GNOME with PaperWM tiling. The session plumbing and
# the GNOME enable folded in here once Mango was the only other option; only
# GNOME remains, so splitting them bought nothing. Server-only GNOME policy
# (no sleep, trimmed background services) stays with the host.
{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";
  services.displayManager.gdm.enable = true;

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

  # GNOME's battery/power indicators read UPower.
  services.upower.enable = true;

  fonts.packages = with pkgs; [ noto-fonts noto-fonts-color-emoji dejavu_fonts ];

  services.desktopManager.gnome.enable = true;

  # PaperWM has no nixpkgs package; upstream's flake packages the extension
  # itself. The system profile drops it where GNOME Shell looks for extensions.
  environment.systemPackages = [ inputs.paperwm.packages.${system}.default ];

  # System-wide default so tiling is on without touching dconf by hand.
  programs.dconf.profiles.user.databases = [{
    settings."org/gnome/shell" = {
      enabled-extensions = [ "paperwm@paperwm.github.com" ];
      disable-user-extensions = false;
    };
  }];
}