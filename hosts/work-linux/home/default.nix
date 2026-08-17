# Ubuntu work laptop — standalone home-manager. GNOME/GDM stays system-managed;
# this host selects its shared user capabilities and supplies local identity.
{ config, inputs, pkgs, ... }:
let
  nixGL = inputs.nixgl.packages.${pkgs.stdenv.hostPlatform.system}.nixGLIntel;
  wrapWithNixGL = name: package:
    pkgs.writeShellScriptBin name ''
      exec ${nixGL}/bin/nixGLIntel ${package}/bin/${name} "$@"
    '';
in
{
  imports = [
    ../../../modules/home/base.nix
    ../../../modules/home/mango.nix
    ../../../modules/home/noctalia.nix
    ../../../modules/home/wezterm.nix
  ];

  home.username = "tu-le5";
  home.homeDirectory = "/home/tu-le5";
  home.stateVersion = "26.11";

  # NixGL supplies the Mesa/EGL runtime required by Nix GUI apps on Ubuntu.
  _module.args = {
    mangoPackage = wrapWithNixGL "mango" pkgs.mango;
    noctaliaPackage = wrapWithNixGL "noctalia" pkgs.noctalia;
    weztermPackage = wrapWithNixGL "wezterm" pkgs.wezterm;
  };

  # GDM reads the system-wide copy installed during Ubuntu setup. Keep its
  # source here so it has an absolute Exec path and is easy to refresh.
  home.file.".local/share/wayland-sessions/mango.desktop".text = ''
    [Desktop Entry]
    Name=Mango
    Comment=Mango Wayland compositor
    Exec=${config.home.profileDirectory}/bin/mango
    Type=Application
    DesktopNames=mango;wlroots
  '';

  nixpkgs.config.allowUnfree = true;

  programs.git.settings.user = {
    name = "tu.le5";
    email = "tu.le5@mservice.com.vn";
  };

  programs.nushell.shellAliases.rebuild = "home-manager switch --flake ~/nix#tu-le5@work-linux";

  # mango is launched by GDM with no login shell, so ~/.nix-profile/bin
  # (mango, noctalia, wezterm) isn't on PATH. Expose it to the session via
  # environment.d so `Exec=mango` and the shared config's bare command names
  # resolve.
  systemd.user.sessionVariables.PATH =
    "${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
}
