# Shared shell, Git, and CLI/TUI tools. Hosts select visual capabilities.
{ pkgs, ... }:
{
  programs.nushell.enable = true;

  programs.git.enable = true;

  # Nord themes: btop's is built in; k9s needs the skin file plus ui.skin.
  programs.btop.enable = true;
  programs.btop.settings.color_theme = "nord";

  programs.k9s.enable = true;
  programs.k9s.settings.k9s.ui.skin = "nord";
  programs.k9s.skins.nord = ./k9s-nord.yaml;

  # Lazygit executes editor commands with Bash even when it detects Nushell.
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

    # Ops
    kubectl
    kubernetes-helm
    argocd
    herdr

    # Noctalia plugin deps
    jq
  ];
}
