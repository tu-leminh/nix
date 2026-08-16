{ ... }:
{
  imports = [
    ../../../modules/home/base.nix
    ../../../modules/home/mango.nix
    ../../../modules/home/noctalia.nix
    ../../../modules/home/wezterm.nix
    ./noctalia.nix
  ];

  home.username = "mt";
  home.homeDirectory = "/home/mt";
  home.stateVersion = "26.11";

  programs.git.settings.user = {
    name = "mt";
    email = "mt.the.dev@gmail.com";
  };

  programs.nushell.shellAliases.rebuild = "sudo nixos-rebuild switch --flake ~/nix#homelab";
}
