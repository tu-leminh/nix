# Graphical (GNOME) bcachefs-enabled installer ISO: boots to a desktop with
# Firefox + a terminal, so the install commands can be copy-pasted from GitHub.
{ modulesPath, pkgs, lib, ... }:
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-graphical-gnome.nix" ];

  boot.kernelPackages = pkgs.linuxPackages_latest; # recent kernel for bcachefs
  boot.supportedFilesystems.bcachefs = true;
  boot.supportedFilesystems.zfs = lib.mkForce false; # zfs won't build on latest kernel

  environment.systemPackages = [ pkgs.keyutils ]; # workaround nixpkgs#32279
}
