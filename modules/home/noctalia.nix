# Noctalia status bar via the official upstream Home Manager module
# (github:noctalia-dev/noctalia). The module installs the package and writes
# ~/.config/noctalia/config.toml; GUI tweaks still land in the app-managed
# ~/.local/state/noctalia/settings.toml, which wins over this file.
{ config, inputs, pkgs, ... }:
let
  noctaliaPackage = config._module.args.noctaliaPackage or pkgs.noctalia;
  wallpaper = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/linuxdotexe/nordic-wallpapers/master/wallpapers/ign_unsplash19.png";
    sha256 = "sha256-rBhO/VsZzcs5xhlwJhGWa5UXJeIVszwh/KD/sJRrfQE=";
  };
in
{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.noctalia = {
    enable = true;
    package = noctaliaPackage;

    settings = {
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Nord";
      };

      wallpaper = {
        enabled = true;
        default.path = "${wallpaper}";
      };

      bar.default = {
        position = "top";
        concave_edge_corners = false;
        margin_ends = 10;
        capsule = true;
        shadow = false;
        contact_shadow = false;
        start = [ "mangowm_keymode" "mango_layouts" "workspaces" "active_window" "media" ];
        center = [ "clock" ];
        end = [ "tray" "notifications" "clipboard" "network" "bluetooth" "volume" "brightness" "battery" "session" "nix_monitor" ];
      };

      dock.shadow = false;

      lockscreen.enabled = true;

      shell = {
        clipboard_enabled = true;
        panel.shadow = false;
        screenshot = {
          save_to_file = true;
          copy_to_clipboard = true;
        };
      };

      widget = {
        media.hide_when_no_media = true;
        workspaces.style = "minimal";
        mangowm_keymode = { type = "gambled23/mangowm-keymode:mangowm-keymode"; };
        nix_monitor = { type = "avivbintangaringga/nix-monitor:nix-monitor"; };
        mango_layouts = { type = "ezequiel/mango_layouts:btn"; };
      };

      plugins = {
        enabled = [
          "ezequiel/mango_layouts"
          "gambled23/mangowm-keymode"
          "avivbintangaringga/nix-monitor"
        ];
      };
    };
  };
}
