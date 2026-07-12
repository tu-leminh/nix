# mt's user environment (home-manager). Apps, CLI tools, and dotfiles live here;
# system-level config stays in modules/.
{ pkgs, ... }:
{
  home.stateVersion = "26.11";

  programs.nushell.enable = true; # login shell is set in modules/users.nix
  programs.git = {
    enable = true;
    settings.user.name = "mt";
    settings.user.email = "mt.the.dev@gmail.com";
  };

  home.packages = with pkgs; [
    # Terminals
    wezterm

    # Browsers
    firefox
    google-chrome

    # Dev / CLI tools
    neovim
    lazygit
    superfile
    claude-code
  ];
}
