{ pkgs, ... }:
{
  home.packages = [ pkgs.wezterm ];

  home.file.".config/wezterm/wezterm.lua".text = ''
    local wezterm = require("wezterm")
    return {
        font_size = 12.0,
        color_scheme = "Catppuccin Mocha",
        enable_tab_bar = false,
    }
  '';
}
