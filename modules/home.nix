# Wires home-manager into NixOS so it's managed by `nixos-rebuild` (no separate
# `home-manager switch`). Per-user config lives in ../home/<user>.nix.
{ ... }:
{
  home-manager.useGlobalPkgs = true;   # share the system nixpkgs (+ its allowUnfree)
  home-manager.useUserPackages = true;
  home-manager.users.mt = import ../home/mt.nix;
}
