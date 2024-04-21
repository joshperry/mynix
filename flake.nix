{
  description = "NixOS configurations";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-23.11"; };
    nixpkgs-unstable = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, nixpkgs-unstable, home-manager, ... }:
  let
    packages = { ... }: {
      nixpkgs.overlays = [
        #pkgs.unstable
        (final: prev: {
          unstable = nixpkgs-unstable.legacyPackages."${prev.system}";
        })

        # Want python310
        #(final: prev: {
        #  python3 = final.python310;
        #  python3Packages = final.python310.pkgs;
        #})
        
        # Private package overlay set
        (final: prev:
          import ./packages { pkgs = final; }
        )
      ]; 
    };
    registry = _: {
      nix.registry = {
        nixpkgs.flake = inputs.nixpkgs;
        nixpkgs-unstable.flake = inputs.nixpkgs-unstable;
      };
    };
  in
  {
    nixosConfigurations = {

      bones = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          packages
          registry
          ./modules
          ./machines/bones/configuration.nix
          ./machines/bones/hardware-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.users.josh = import ./users/josh;

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };

      liver = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          packages
          registry
          ./modules
          ./machines/liver/configuration.nix
          ./machines/liver/hardware-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.users.josh = import ./users/josh/server.nix;

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };

      mantissa = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          packages
          registry
          ./modules
          ./machines/mantissa/configuration.nix
          ./machines/mantissa/hardware-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.users.josh = import ./users/josh;

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };

      xeeps = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          packages
          registry
          ./modules
          ./machines/xeeps/configuration.nix
          ./machines/xeeps/hardware-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.users.josh = ({...}: {
              imports = [./users/josh ./users/josh/solo.nix];
            });

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };
      
    };
  };
}
