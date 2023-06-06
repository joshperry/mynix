{
  description = "Bones NixOS configuration";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-23.05"; };
    nixos-unstable = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, nixos-unstable, home-manager, ... }: {
    nixosConfigurations = {

      bones = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          #nixpkgs overlay(s)
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [
              (final: prev: {
                #pkgs.unstable
                unstable = import nixos-unstable {
                  inherit (prev) system; 
                };

              })
            ]; 
          })
          ./machines/bones/configuration.nix
          ./machines/bones/hardware-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.users.josh = import ./users/josh.nix;

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };
      
    };
  };
}
