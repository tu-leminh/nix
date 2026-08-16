# Personal NixOS defaults. Machine facts and access policy stay under hosts/.
{ pkgs, lib, ... }:
{
  hardware.enableRedistributableFirmware = lib.mkDefault true;
  networking.networkmanager.enable = lib.mkDefault true;

  nixpkgs.config.allowUnfree = lib.mkDefault true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = lib.mkDefault "Asia/Ho_Chi_Minh";

  environment.systemPackages = with pkgs; [ git vim nushell ];
}
