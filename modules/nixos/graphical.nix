# Shared graphical session plumbing. GNOME and Mango stay separate imports.
{ pkgs, ... }:
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

  # Noctalia uses UPower for battery and power widgets.
  services.upower.enable = true;

  fonts.packages = with pkgs; [ noto-fonts noto-fonts-color-emoji dejavu_fonts ];
}
