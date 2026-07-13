# Wires home-manager into NixOS so it's managed by `nixos-rebuild` (no separate
# `home-manager switch`). Per-user config lives in ../user/default.nix.
{ ... }:
{
  home-manager.useGlobalPkgs = true;   # share the system nixpkgs (+ its allowUnfree)
  home-manager.useUserPackages = true;
  home-manager.users.mt = import ../user/default.nix;
}
