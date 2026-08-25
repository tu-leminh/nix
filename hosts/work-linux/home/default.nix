# Ubuntu work laptop — standalone home-manager. GNOME/GDM stays system-managed;
# this host selects its shared user capabilities and supplies local identity.
{ config, pkgs, ... }:
{
  imports = [
    ../../../modules/home/base.nix
    ../../../modules/home/lazyvim.nix
    ../../../modules/home/gnome.nix
    ../../../modules/home/gnome-keys.nix
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

  nixpkgs.config.allowUnfree = true;

  # Work-only dev tooling: momo builds via Bazelisk, which reads the repo's
  # .bazelversion to fetch the pinned Bazel. nixpkgs' bazelisk installs only
  # the bazelisk binary, so expose it under the usual "bazel" name too. GKE
  # kubeconfigs invoke this SDK component directly for kubectl authentication.
  # uv lives in shared base.nix.
  home.packages = with pkgs; [
    (google-cloud-sdk.withExtraComponents [
      google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])
    skaffold
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

  # rc.d/ drop-in rather than ~/.xonshrc, which base.nix owns.
  xdg.configFile."xonsh/rc.d/rebuild.xsh".text = ''
    aliases["rebuild"] = "home-manager switch --flake ~/nix#tu-le5@work-linux"
  '';

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

  # GNOME-spawned apps (WezTerm, browsers) resolve nix commands through
  # environment.d; the interactive bash shell gets them from hm-session-vars.sh
  # plus the nix profile that targets.genericLinux adds to programs.bash.
  systemd.user.sessionVariables.PATH =
    "${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
}
