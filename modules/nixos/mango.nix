{ pkgs, ... }:
{
  services.displayManager.sessionPackages = [ pkgs.mango ];
}
