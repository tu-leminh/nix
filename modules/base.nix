# Host-agnostic base: bootloader, networking stack, common tooling.
# Per-host bits (hostname, stateVersion, disks, static IP) live under hosts/.
{ pkgs, ... }:
{
  imports = [ ./users.nix ./ssh.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "bcachefs" ];

  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  nixpkgs.config.allowUnfree = true; # google-chrome, claude-code

  time.timeZone = "Asia/Ho_Chi_Minh";

  environment.systemPackages = with pkgs; [ bcachefs-tools keyutils git vim btop nushell ];
}
