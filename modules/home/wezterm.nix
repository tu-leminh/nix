{ config, pkgs, ... }:
let
  weztermPackage = config._module.args.weztermPackage or pkgs.wezterm;
  jetbrainsMono = pkgs.nerd-fonts.jetbrains-mono;
  # WezTerm's hardware front ends hard-hang the work laptop's i915 GPU
  # (kernel context resets freeze the window and stutter the whole desktop):
  # WebGpu/Vulkan first, then OpenGL/desktop-GL too. Software is the only
  # stable path there, while mango/noctalia stay fine on GLES/EGL - so that
  # laptop opts out via _module.args.weztermFrontEnd instead of this module
  # forcing software rendering on healthy GPUs.
  frontEnd = config._module.args.weztermFrontEnd or "WebGpu";
in
{
  home.packages = [
    weztermPackage
    # LazyVim and other TUIs need nerd-font glyphs.
    jetbrainsMono
  ];

  # Registers the profile's fonts on generic Linux (Ubuntu) too.
  fonts.fontconfig.enable = true;

  home.file.".config/wezterm/wezterm.lua".text = ''
    local wezterm = require("wezterm")
    local scheme = wezterm.color.get_builtin_schemes()["nord"]

    -- All tab-bar shades derive from the nord palette itself; no hardcoded colors.
    local function lighter(amount)
      return wezterm.color.parse(scheme.background):lighten(amount)
    end

    return {
        -- Use the immutable store path so config reloads during profile
        -- switches do not race Fontconfig's view of ~/.nix-profile.
        font_dirs = { "${jetbrainsMono}/share/fonts/truetype/NerdFonts/JetBrainsMono" },
        font = wezterm.font("JetBrainsMono Nerd Font"),
        font_size = 10.0,
        color_scheme = "nord",
        default_prog = { "nu" },
        -- Hardware front ends reset the work laptop's i915 GPU; see the
        -- frontEnd comment in modules/home/wezterm.nix.
        front_end = "${frontEnd}",
        window_background_opacity = 0.5,
        text_background_opacity = 0.5,
        enable_tab_bar = true,
        use_fancy_tab_bar = true,
        keys = {
            {
                key = "W",
                mods = "CTRL|SHIFT",
                action = wezterm.action.CloseCurrentTab { confirm = false },
            },
        },
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
