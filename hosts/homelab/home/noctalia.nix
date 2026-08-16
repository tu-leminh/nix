# homelab-only nix-monitor settings: the Update button needs an actual
# rebuild command (shared module leaves update_command empty).
{ ... }:
{
  programs.noctalia.settings.plugin_settings."avivbintangaringga/nix-monitor" = {
    update_command = "sudo nixos-rebuild switch --flake ~/nix#homelab";
  };
}
