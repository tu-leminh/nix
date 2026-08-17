{ config, pkgs, ... }:
let
  weztermPackage = config._module.args.weztermPackage or pkgs.wezterm;
in
{
  home.packages = [ weztermPackage ];

  home.file.".config/wezterm/wezterm.lua".text = ''
    local wezterm = require("wezterm")
    return {
        font_size = 12.0,
        color_scheme = "nord",
        enable_tab_bar = true,
        front_end = "Software",
    }
  '';
}
