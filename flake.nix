{
  description = "NixOS configurations";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-23.05"; };
    nixos-unstable = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, nixos-unstable, home-manager, ... }:
  let
    packages = { ... }: {
      nixpkgs.overlays = [
        #pkgs.unstable
        (final: prev: {
          unstable = nixos-unstable.legacyPackages."${prev.system}";
        })

        # Want python310
        (final: prev: {
          python3 = final.python310;
          python3Packages = final.python310.pkgs;
        })
        
        # Private package overlay set
        (final: prev:
          import ./packages { pkgs = final; }
        )
      ]; 
    };
  in
  {
    nixosConfigurations = {

      bones = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          packages
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

      xeeps = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          packages
          (_: { nix.registry.nixpkgs.flake = inputs.nixpkgs; })
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
