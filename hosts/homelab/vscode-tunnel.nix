# Remote access via VS Code tunnel (code tunnel). nix-ld lets the tunnel's
# unpatched, dynamically-linked server binary run on NixOS.
#
# First-time setup (interactive, once):
#   code tunnel --accept-server-license-terms
# Follow the device-code URL to authenticate; the token is cached under
# ~/.vscode / ~/.local/share so the service below can reuse it afterwards.
{ pkgs, ... }:
{
  programs.nix-ld.enable = true;

  environment.systemPackages = [ pkgs.vscode ];

  systemd.user.services.code-tunnel = {
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.vscode}/bin/code tunnel --accept-server-license-terms --name homelab";
      Restart = "always";
    };
  };

  users.users.mt.linger = true;
}
