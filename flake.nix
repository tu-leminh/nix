{
  description = "NixOS homelab + Ubuntu work laptop (home-manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    noctalia.url = "github:noctalia-dev/noctalia";
    noctalia.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self, nixpkgs, disko, home-manager, noctalia, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations.homelab = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          ./hosts/homelab/nixos
        ];
      };

      # Bootable bcachefs installer image
      nixosConfigurations.installer = lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/homelab/nixos/installer.nix ];
      };

      # Ubuntu work laptop — standalone home-manager
      homeConfigurations."tu-le5@work-linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./hosts/work-linux/home ];
      };

      # `nix build .#iso`
      packages.${system}.iso = self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
