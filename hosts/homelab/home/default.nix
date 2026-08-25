{ pkgs, ... }:
{
  imports = [
    ../../../modules/home/base.nix
    ../../../modules/home/lazyvim.nix
    ../../../modules/home/gnome-keys.nix
    ../../../modules/home/wezterm.nix
    ../../../modules/home/vscode.nix
  ];

  home.username = "mt";
  home.homeDirectory = "/home/mt";
  home.stateVersion = "26.11";

  home.packages = [ pkgs.google-chrome ];

  programs.git.settings.user = {
    name = "mt";
    email = "mt.the.dev@gmail.com";
  };

  # rc.d/ drop-in rather than ~/.xonshrc, which base.nix owns.
  xdg.configFile."xonsh/rc.d/rebuild.xsh".text = ''
    aliases["rebuild"] = "sudo nixos-rebuild switch --flake ~/nix#homelab"
  '';

  services.vscode-tunnel = {
    enable = true;
    executable = "${pkgs.vscode}/bin/code";
    tunnelName = "homelab";
    # A lingered user manager has a minimal PATH. Keep the normal user and
    # system tools available to terminals opened through the remote server.
    servicePath = [
      pkgs.bash
      "/run/wrappers"
      "/etc/profiles/per-user/mt"
      "/run/current-system/sw"
    ];
  };
}
