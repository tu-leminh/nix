# Base host config. Mounts come from ../disko.
{ pkgs, ... }:
{
  imports = [ ./users.nix ./ssh.nix ./network.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "bcachefs" ];

  networking.hostName = "homelab";
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  time.timeZone = "Asia/Ho_Chi_Minh";

  environment.systemPackages = with pkgs; [ bcachefs-tools keyutils git vim ];

  system.stateVersion = "26.11";
}
