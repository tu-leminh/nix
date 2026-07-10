{
  description = "Bcachefs installer ISO + tiered 5-disk home-lab host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, disko }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        # Bootable bcachefs installer image.
        installer = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./modules/iso ];
        };

        # The installed machine: disko pool + base + desktop + k3s.
        homelab = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            disko.nixosModules.disko
            ./modules/disko
            ./modules/system
            ./modules/desktop
            ./modules/k3s
          ];
        };
      };

      # `nix build .#iso`
      packages.${system}.iso = self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
