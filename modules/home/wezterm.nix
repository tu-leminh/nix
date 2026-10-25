{ config, pkgs, ... }:
let
  jetbrainsMono = pkgs.nerd-fonts.jetbrains-mono;
  # WezTerm's hardware front ends hard-hang the work laptop's i915 GPU
  # (kernel context resets freeze the window and stutter the whole desktop):
  # WebGpu/Vulkan first, then OpenGL/desktop-GL too. Software is the only
  # stable path there, so that laptop opts out via _module.args.weztermFrontEnd
  # instead of this module forcing software rendering on healthy GPUs.
  frontEnd = config._module.args.weztermFrontEnd or "WebGpu";
in
{
  home.packages = with pkgs; [
    wezterm
    # LazyVim and other TUIs need nerd-font glyphs.
    jetbrainsMono
  ];

  # Registers the profile's fonts on generic Linux (Ubuntu) too.
  fonts.fontconfig.enable = true;

  home.file.".config/wezterm/wezterm.lua".text = ''
    local wezterm = require("wezterm")
    local scheme = wezterm.color.get_builtin_schemes()["nord"]

    -- Window-frame shades derive from the nord palette itself; no hardcoded colors.
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
        default_prog = { "xonsh" },
        -- Hardware front ends reset the work laptop's i915 GPU; see the
        -- frontEnd comment in modules/home/wezterm.nix.
        front_end = "${frontEnd}",
        window_background_opacity = 1.0,
        text_background_opacity = 1.0,
        enable_tab_bar = false,
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
    }
  '';
}
