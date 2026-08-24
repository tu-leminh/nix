# Ubuntu work laptop — standalone home-manager. GNOME/GDM stays system-managed;
# this host selects its shared user capabilities and supplies local identity.
{ config, pkgs, ... }:
{
  imports = [
    ../../../modules/home/base.nix
    ../../../modules/home/mango.nix
    ../../../modules/home/noctalia.nix
    ../../../modules/home/wezterm.nix
    ../../../modules/home/vscode.nix
  ];

  home.username = "tu-le5";
  home.homeDirectory = "/home/tu-le5";
  home.stateVersion = "26.11";

  # WezTerm's WebGpu and OpenGL front ends both reset this laptop's i915 GPU
  # (see modules/home/wezterm.nix); software rendering is the only mode that
  # survives here.
  _module.args.weztermFrontEnd = "Software";

  # Make Ubuntu's Mesa/EGL drivers available to every Nix GUI app.
  targets.genericLinux.enable = true;

  # GDM reads the system-wide copy installed during Ubuntu setup. Keep its
  # source here so it has an absolute Exec path and is easy to refresh.
  home.file.".local/share/wayland-sessions/mango.desktop".text = ''
    [Desktop Entry]
    Name=Mango
    Comment=Mango Wayland compositor
    Exec=${config.home.homeDirectory}/.config/mango/launch
    Type=Application
    DesktopNames=mango;wlroots
  '';

  # GDM hands Mango Ubuntu's stock PATH, so bare commands in Mango's
  # exec-once/keybinds cannot resolve. The wrapper also guarantees the Nix
  # profile's desktop entries remain discoverable to the whole session.
  home.file.".config/mango/launch" = {
    executable = true;
    text = ''
      #!/bin/sh
      export PATH="${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:$PATH"
      export XDG_DATA_DIRS="${config.home.profileDirectory}/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
      exec "${config.home.profileDirectory}/bin/mango" "$@"
    '';
  };

  nixpkgs.config.allowUnfree = true;

  # Work-only dev tooling: momo builds via Bazelisk, which reads the repo's
  # .bazelversion to fetch the pinned Bazel. nixpkgs' bazelisk installs only
  # the bazelisk binary, so expose it under the usual "bazel" name too.
  # uv lives in shared base.nix.
  home.packages = with pkgs; [
    (pkgs.symlinkJoin {
      name = "bazelisk-bazel";
      paths = [ pkgs.bazelisk ];
      postBuild = "ln -s ${pkgs.bazelisk}/bin/bazelisk $out/bin/bazel";
    })
  ];

  programs.git.settings.user = {
    name = "tu.le5";
    email = "tu.le5@mservice.com.vn";
  };

  programs.nushell.shellAliases.rebuild = "home-manager switch --flake ~/nix#tu-le5@work-linux";

  # VS Code itself is installed and updated by Ubuntu's Microsoft APT source.
  # The shared Home Manager capability only owns the user service.
  services.vscode-tunnel = {
    enable = true;
    executable = "/usr/bin/code";
    tunnelName = "work-linux";
    servicePath = [
      config.home.profileDirectory
      "/usr/local"
      "/usr"
    ];
  };

  # Terminals and user units resolve nix commands via environment.d below;
  # the GDM->mango session chain ignores it (it takes PATH from PAM), which
  # is why .config/mango/launch exists.
  systemd.user.sessionVariables.PATH =
    "${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
}
