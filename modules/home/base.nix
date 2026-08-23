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

  home.packages = with pkgs; [
    # Dev / AI CLIs
    neovim
    lazygit
    superfile
    claude-code
    codex
    antigravity-ide
    opencode

    # Ops
    kubectl
    kubernetes-helm
    argocd
    herdr

    # Noctalia plugin deps
    jq
  ];
}
