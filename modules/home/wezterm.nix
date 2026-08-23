{ config, pkgs, ... }:
let
  weztermPackage = config._module.args.weztermPackage or pkgs.wezterm;
in
{
  home.packages = [ weztermPackage ];

  home.file.".config/wezterm/wezterm.lua".text = ''
    local wezterm = require("wezterm")
    local scheme = wezterm.color.get_builtin_schemes()["nord"]

    -- All tab-bar shades derive from the nord palette itself; no hardcoded colors.
    local function lighter(amount)
      return wezterm.color.parse(scheme.background):lighten(amount)
    end

    return {
        font_size = 10.0,
        color_scheme = "nord",
        default_prog = { "nu" },
        enable_tab_bar = true,
        use_fancy_tab_bar = true,
        window_frame = {
            font_size = 10.0,
            active_titlebar_bg = lighter(0.04),
            inactive_titlebar_bg = lighter(0.02),
        },
        colors = {
            tab_bar = {
                active_tab = { bg_color = scheme.ansi[7], fg_color = scheme.background },
                inactive_tab = {
                    bg_color = lighter(0.06),
                    fg_color = wezterm.color.parse(scheme.foreground):darken(0.35),
                },
                inactive_tab_hover = { bg_color = lighter(0.12), fg_color = scheme.foreground },
                new_tab = {
                    bg_color = lighter(0.04),
                    fg_color = wezterm.color.parse(scheme.foreground):darken(0.35),
                },
                new_tab_hover = { bg_color = lighter(0.12), fg_color = scheme.foreground },
            },
        },
    }
  '';
}
