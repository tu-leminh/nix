# Shared shell, Git, and CLI/TUI tools. Hosts select visual capabilities.
{ config, lib, pkgs, ... }:
{
  # GNOME Terminal is bash on both hosts. Enabling it also activates the
  # targets.genericLinux hook that sources nix.sh and hm-session-vars.sh,
  # which was silently dead on the Ubuntu laptop.
  programs.bash.enable = true;

  # zoxide keeps `z`/`zi` alongside a normal `cd`; options stays empty on
  # purpose. Its bash hook rides on programs.bash above.
  programs.zoxide.enable = true;

  # Neither Home Manager nor its zoxide module has a xonsh hook, so this is
  # upstream's init line wired by hand. The store path keeps it working under
  # a minimal PATH.
  home.file.".xonshrc".text = ''
    execx($(${lib.getExe config.programs.zoxide.package} init xonsh), 'exec', __xonsh__.ctx, filename='zoxide')
  '';

  programs.git.enable = true;

  # Nord themes: btop's is built in; k9s needs the skin file plus ui.skin.
  programs.btop.enable = true;
  programs.btop.settings.color_theme = "nord";

  programs.k9s.enable = true;
  programs.k9s.settings.k9s.ui.skin = "nord";
  programs.k9s.skins.nord = ./k9s-nord.yaml;

  # Lazygit runs its editor commands through Bash regardless of the login
  # shell, so these stay plain shell syntax.
  xdg.configFile."lazygit/config.yml".text = ''
    os:
      edit: '[ -z "$NVIM" ] && (nvim -- {{filename}}) || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote-tab {{filename}})'
      editAtLine: '[ -z "$NVIM" ] && (nvim +{{line}} -- {{filename}}) || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote-tab {{filename}} && nvim --server "$NVIM" --remote-send ":{{line}}<CR>")'
      openDirInEditor: '[ -z "$NVIM" ] && (nvim -- {{dir}}) || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote-tab {{dir}})'
  '';

  home.packages = with pkgs; [
    # Dev / AI CLIs
    lazygit
    superfile
    claude-code
    codex
    antigravity-ide
    opencode
    uv
    mise

    # Ops
    kubectl
    kubernetes-helm
    argocd
    herdr
    sops
    age

    # WezTerm's default shell, plus fzf for zoxide's interactive `zi` picker
    xonsh
    fzf
  ];
}