{
  description = "NixOS homelab + Ubuntu work-linux + macOS work-mac";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # darwin.url = "github:lnl7/nix-darwin";
    # darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, disko, home-manager }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations.homelab = lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          ./hosts/homelab
        ];
      };

      # Bootable bcachefs installer image
      nixosConfigurations.installer = lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/installer ];
      };

      # Ubuntu work laptop — standalone home-manager
      homeConfigurations."mt@work-linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = [ ./hosts/work-linux/home.nix ];
      };

      # `nix build .#iso`
      packages.${system}.iso = self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
