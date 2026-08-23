# Makes inputs available to the home-manager configs (e.g. the official
# noctalia module). Each host supplies its own users and home modules.
{ inputs, ... }:
{
  home-manager.useGlobalPkgs = true;   # share the system nixpkgs (+ its allowUnfree)
  home-manager.useUserPackages = true;
  # Rename pre-existing plain files (e.g. hand-made k9s/btop configs) to
  # *.backup instead of failing the activation.
  home-manager.backupFileExtension = "backup";
  home-manager.extraSpecialArgs = { inherit inputs; };
}