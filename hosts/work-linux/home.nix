{ ... }:
{
  # Ubuntu work laptop — standalone home-manager (no NixOS system config).
  # User packages and dotfiles only.

  imports = [ ../../user/default.nix ];

  home.username = "mt";
  home.homeDirectory = "/home/mt";

  nixpkgs.config.allowUnfree = true;
}
