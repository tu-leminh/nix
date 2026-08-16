# Noctalia status bar via the official upstream Home Manager module
# (github:noctalia-dev/noctalia). The module installs the package and writes
# ~/.config/noctalia/config.toml; GUI tweaks still land in the app-managed
# ~/.local/state/noctalia/settings.toml, which wins over this file.
{ inputs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.noctalia = {
    enable = true;

    settings = {
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Nord";
      };

      bar.default = {
        position = "top";
        concave_edge_corners = false;
        margin_ends = 10;
        capsule = true;
        start = [ "workspaces" "active_window" "media" ];
        center = [ "clock" ];
        end = [ "tray" "notifications" "clipboard" "network" "bluetooth" "volume" "brightness" "battery" "session" ];
      };

      widget.media.hide_when_no_media = true;
    };
  };
}