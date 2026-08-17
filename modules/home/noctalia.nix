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
        end = [
          "sysmon_cpu"
          "sysmon_cpu_temp"
          "sysmon_gpu_temp"
          "sysmon_gpu_usage"
          "sysmon_gpu_vram"
          "sysmon_ram_used"
          "sysmon_ram_pct"
          "sysmon_swap_pct"
          "sysmon_disk_pct"
          "sysmon_net_rx"
          "sysmon_net_tx"
          "tray"
          "notifications"
          "clipboard"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "battery"
          "session"
          "nix_monitor"
        ];
      };

      system.monitor = {
        enabled = true;
        cpu_poll_seconds = 2.0;
        gpu_poll_seconds = 5.0;
        memory_poll_seconds = 2.0;
        network_poll_seconds = 3.0;
        disk_poll_seconds = 10.0;
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

        sysmon_cpu = {
          type = "sysmon";
          stat = "cpu_usage";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_cpu_temp = {
          type = "sysmon";
          stat = "cpu_temp";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_gpu_temp = {
          type = "sysmon";
          stat = "gpu_temp";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_gpu_usage = {
          type = "sysmon";
          stat = "gpu_usage";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_gpu_vram = {
          type = "sysmon";
          stat = "gpu_vram";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_ram_used = {
          type = "sysmon";
          stat = "ram_used";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_ram_pct = {
          type = "sysmon";
          stat = "ram_pct";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_swap_pct = {
          type = "sysmon";
          stat = "swap_pct";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_disk_pct = {
          type = "sysmon";
          stat = "disk_pct";
          path = "/";
          display = "text";
          show_label = true;
          label_show_units = true;
        };
        sysmon_net_rx = {
          type = "sysmon";
          stat = "net_rx";
          display = "text";
          show_label = true;
          label_show_units = true;
          network_speed_unit = "auto";
          network_speed_compact = true;
        };
        sysmon_net_tx = {
          type = "sysmon";
          stat = "net_tx";
          display = "text";
          show_label = true;
          label_show_units = true;
          network_speed_unit = "auto";
          network_speed_compact = true;
        };
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
