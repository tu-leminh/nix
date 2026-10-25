# GNOME capability for a distro-managed session (Ubuntu). PaperWM is the same
# extension the NixOS side installs, but GDM starts GNOME outside the Nix
# profile there, so XDG_DATA_DIRS cannot be relied on to locate it. The user
# extension dir is always scanned, so link it in instead.
{ config, inputs, pkgs, ... }:
let
  paperwm = inputs.paperwm.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # The package installs itself under share/gnome-shell/extensions/<uuid>.
  # GNOME Shell reads metadata.json from that inner directory, so link *it*:
  # pointing at the package root leaves the extension looking for a
  # metadata.json one level too high and it silently fails to register.
  extensionDir = "${paperwm}/share/gnome-shell/extensions/${paperwm.extensionUuid}";
in
{
  home.file."${config.xdg.dataHome}/gnome-shell/extensions/${paperwm.extensionUuid}".source =
    extensionDir;

  dconf.settings."org/gnome/shell" = {
    enabled-extensions = [ paperwm.extensionUuid ];
    disable-user-extensions = false;
  };
}