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
    nixosSystem = { name, system, users }: 
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          packages
          registry
          ./modules
          ./machines/${name}/configuration.nix
          ./machines/${name}/hardware-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.users = users;

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };
  in
  {
    nixosConfigurations = {

      bones = nixosSystem {
        name = "bones";
        system = "x86_64-linux";
        users = {
          josh = import ./users/josh;
        };
      };

      liver = nixosSystem {
        name = "liver";
        system = "x86_64-linux";
        users = {
          josh = import ./users/josh/server.nix;
        };
      };

      mantissa = nixosSystem {
        name = "mantissa";
        system = "x86_64-linux";
        users = {
          josh = import ./users/josh;
        };
      };

      xeeps = nixosSystem {
        name = "xeeps";
        system = "x86_64-linux";
        users = {
          josh = ({...}: {
            imports = [./users/josh ./users/josh/solo.nix];
          });
        };
      };
      
    };
  };
}
