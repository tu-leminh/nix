# Makes inputs available to the home-manager configs (e.g. the official
# noctalia module). Each host supplies its own users and home modules.
{ inputs, ... }:
{
  home-manager.useGlobalPkgs = true;   # share the system nixpkgs (+ its allowUnfree)
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit inputs; };
}