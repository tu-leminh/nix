# Remote access via VS Code tunnel (code tunnel). nix-ld lets the tunnel's
# unpatched, dynamically-linked server binary run on NixOS.
#
# First-time setup (interactive, once) — auth token MUST land in a file, not
# the keyring, or the headless boot below can't read it:
#   export VSCODE_CLI_USE_FILE_KEYCHAIN=1
#   code tunnel user login --provider github
#   code tunnel --accept-server-license-terms
# `code tunnel` stores its GitHub token in the gnome-keyring by default, but the
# keyring is locked on a headless boot (nothing enters the login password), so
# the service would silently re-prompt for device-code login every reboot.
# VSCODE_CLI_USE_FILE_KEYCHAIN=1 forces the CLI to use a plaintext
# ~/.vscode/cli/token.json instead, which the service can read on every boot.
# That file is imperative state (like the argohome deploy key) — not in the
# flake, so re-do this login once after a reinstall.
{ pkgs, ... }:
{
  programs.nix-ld.enable = true;

  environment.systemPackages = [ pkgs.vscode ];

  systemd.user.services.code-tunnel = {
    wantedBy = [ "default.target" ];
    environment.VSCODE_CLI_USE_FILE_KEYCHAIN = "1";
    # `path` fully replaces this unit's PATH rather than extending whatever the
    # manager would otherwise supply — since the service starts via linger (no
    # login session), that means every terminal/process spawned through the
    # tunnel only sees what's listed here. `pkgs.bash` alone is needed so the
    # `code` CLI's internal `env sh` doesn't exit 127; the three raw paths
    # (each gets "/bin" appended) restore sudo, home-manager user packages
    # (e.g. superfile), and system packages (e.g. k9s) for tunnel terminals.
    path = [
      pkgs.bash
      "/run/wrappers"
      "/etc/profiles/per-user/mt"
      "/run/current-system/sw"
    ];
    serviceConfig = {
      ExecStart = "${pkgs.vscode}/bin/code tunnel --accept-server-license-terms --name homelab";
      Restart = "always";
      RestartSec = 5;
    };
  };

  users.users.mt.linger = true;
}
