# NixOS runtime for the shared Home Manager VS Code tunnel service. nix-ld lets
# the tunnel's unpatched, dynamically-linked server binary run on NixOS.
{ pkgs, ... }:
{
  programs.nix-ld.enable = true;

  environment.systemPackages = [ pkgs.vscode ];

  users.users.mt.linger = true;
}
