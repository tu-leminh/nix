# LazyVim capability: home-manager owns the config; lazy.nvim installs and
# pins plugins at runtime from the vendored lazy-lock.json. Mason stays stock
# (works on Ubuntu; on NixOS nix-ld covers most prebuilt tools). gcc is here
# for treesitter parser builds, ripgrep for telescope live-grep.
{ pkgs, lib, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  home.packages = with pkgs; [
    ripgrep
    gcc
  ];

  xdg.configFile."nvim".source = ./nvim;

  # lazy.nvim/LazyVim keep their mutable state in the data dir (the config is
  # a read-only store path). Re-seed the pinned lockfile/extras every switch,
  # so a switch re-asserts the repo pins; runtime :Lazy update writes there
  # freely in between.
  home.activation.lazyvimState =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.local/share/nvim"
      cp -f ${./nvim/lazy-lock.json} "$HOME/.local/share/nvim/lazy-lock.json"
      chmod u+w "$HOME/.local/share/nvim/lazy-lock.json"
      cp -f ${./nvim/lazyvim.json} "$HOME/.local/share/nvim/lazyvim.json"
      chmod u+w "$HOME/.local/share/nvim/lazyvim.json"
    '';
}
