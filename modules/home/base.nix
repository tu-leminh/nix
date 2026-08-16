# Shared shell, Git, and CLI/TUI tools. Hosts select visual capabilities.
{ pkgs, ... }:
{
  programs.nushell.enable = true;

  programs.git.enable = true;

  home.packages = with pkgs; [
    # Dev / AI CLIs
    neovim
    lazygit
    superfile
    claude-code
    codex
    antigravity
    opencode

    # Ops
    btop
    kubectl
    k9s
    kubernetes-helm
    argocd
    herdr

    # Browsers
    google-chrome
  ];
}
