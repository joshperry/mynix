{
  description = "NixOS configurations";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-24.11"; };
    nixpkgs-unstable = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = { url = "github:nix-community/impermanence"; };
  };

  outputs = inputs@{ nixpkgs, nixpkgs-unstable, home-manager, ... }:
  let
    packages = { ... }: {
      nixpkgs.overlays = [
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
    nixosSystem = { name, system, users, sysmodules ? [] }: 
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          packages
          registry
          ./modules
          ./machines/${name}/configuration.nix
          ./machines/${name}/hardware-configuration.nix
          ({config, ...}: {
            nixpkgs.overlays = [
              #pkgs.unstable
              (final: prev: {
                unstable = import nixpkgs-unstable {
                  inherit system;
                  config.allowUnfreePredicate = config.nixpkgs.config.allowUnfreePredicate; 
                };
              })
            ];
          })
          home-manager.nixosModules.home-manager
          {
            home-manager.users = users;

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ] ++ sysmodules;
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

      signi = nixosSystem {
        name = "signi";
        system = "x86_64-linux";
        users = {
          josh = import ./users/josh;
        };
        sysmodules = [
          inputs.impermanence.nixosModules.impermanence
        ];
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
