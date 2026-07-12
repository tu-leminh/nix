{
  description = "Bcachefs installer ISO + tiered NixOS home-lab hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, disko, home-manager }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      # Every directory under hosts/ becomes a nixosConfiguration of that name.
      hostNames = builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./hosts));
      mkHost = name: lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          (./hosts + "/${name}")
        ];
      };
    in
    {
      nixosConfigurations = lib.genAttrs hostNames mkHost // {
        # Bootable bcachefs installer image (not a real host).
        installer = lib.nixosSystem {
          inherit system;
          modules = [ ./modules/iso.nix ];
        };
      };

      # `nix build .#iso`
      packages.${system}.iso = self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
