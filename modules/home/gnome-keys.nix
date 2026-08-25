# Mango's keybindings carried over to GNOME + PaperWM, so muscle memory
# survives the switch. Mango "tags" become fixed GNOME workspaces. Binds with
# no counterpart (layout switching, gaps, minimize, pixel move/resize) are
# dropped rather than faked.
{ lib, ... }:
let
  workspaces = lib.range 1 9;
  perWorkspace = prefix: key:
    lib.listToAttrs (map
      (n: lib.nameValuePair "${prefix}-${toString n}" [ (key n) ])
      workspaces);
in
{
  dconf.settings = {
    "org/gnome/shell/extensions/paperwm/keybindings" = {
      # Focus / move windows (Mango focusdir / exchange_client). PaperWM's own
      # Super+arrow keys stay alongside Mango's Alt+arrow / Super+Shift+arrow.
      switch-left = [ "<Super>Left" "<Alt>Left" ];
      switch-right = [ "<Super>Right" "<Alt>Right" ];
      switch-up = [ "<Super>Up" "<Alt>Up" ];
      switch-down = [ "<Super>Down" "<Alt>Down" ];
      move-left = [ "<Super><Ctrl>Left" "<Super><Shift>Left" ];
      move-right = [ "<Super><Ctrl>Right" "<Super><Shift>Right" ];
      move-up = [ "<Super><Ctrl>Up" "<Super><Shift>Up" ];
      move-down = [ "<Super><Ctrl>Down" "<Super><Shift>Down" ];

      # Mango's focusstack and togglejump. Super+Tab moves to the next window;
      # Alt+Tab returns to the previous one.
      switch-next = [ "<Super>Tab" ];
      switch-previous = [ "<Super><Shift>Tab" ];
      live-alt-tab = [ "<Alt>Tab" ];
      live-alt-tab-backward = [ "<Alt><Shift>Tab" ];

      close-window = [ "<Alt>q" ];
      toggle-maximize-width = [ "<Super>f" "<Alt>f" "<Alt>a" "<Alt>e" ];
      cycle-width = [ "<Alt>x" ];
      toggle-scratch = [ "<Alt>z" ];

      # Mango's focusmon / tagmon. The vertical monitor defaults and swap-*
      # would collide with the keys above, so they are cleared.
      switch-monitor-left = [ "<Alt><Shift>Left" ];
      switch-monitor-right = [ "<Alt><Shift>Right" ];
      move-monitor-left = [ "<Super><Alt>Left" ];
      move-monitor-right = [ "<Super><Alt>Right" ];
      switch-monitor-above = [ ];
      switch-monitor-below = [ ];
      swap-monitor-left = [ ];
      swap-monitor-right = [ ];
      swap-monitor-above = [ ];
      swap-monitor-below = [ ];
    };

    # PaperWM's switch-first (Super+Home) collides with GNOME's
    # switch-to-workspace-1 default (also Super+Home), so PaperWM blanks the
    # GNOME key and stashes the original in this save list — restoring and
    # re-blanking it on every conflict re-check, which killed Ctrl+1 while
    # Ctrl+2..9 (empty defaults) kept working. Clearing the list stops the
    # restore so Ctrl+1 sticks. Side effect: PaperWM can no longer undo any
    # GNOME keybind it blanks if it is ever disabled.
    "org/gnome/shell/extensions/paperwm".restore-keybinds = "{}";

    "org/gnome/desktop/wm/keybindings" =
      perWorkspace "switch-to-workspace" (n: "<Ctrl>${toString n}")
      // perWorkspace "move-to-workspace" (n: "<Alt>${toString n}")
      // {
        # Super+Space opens the launcher (below), not the input-source picker.
        switch-input-source = [ ];
        switch-input-source-backward = [ ];
      };

    # Mango tags are a fixed set, not GNOME's on-demand workspaces.
    "org/gnome/mutter".dynamic-workspaces = false;
    "org/gnome/desktop/wm/preferences".num-workspaces = 9;

    "org/gnome/shell/keybindings" = {
      toggle-overview = [ "<Super>space" ];
      show-screenshot-ui = [ "Print" "<Super><Shift>s" ];
      # Super+s already opens quick settings, as Mango's control center did.
      toggle-quick-settings = [ "<Super>s" ];
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      screensaver = [ "<Super>l" ];
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal" = {
      name = "WezTerm";
      command = "wezterm start";
      binding = "<Alt>Return";
    };
  };
}
