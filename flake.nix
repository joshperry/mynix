{
  description = "NixOS configurations";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-25.05"; };
    nixpkgs-unstable = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = { url = "github:nix-community/impermanence"; };
    flake-parts.url = "github:hercules-ci/flake-parts";
  };


  outputs = inputs@{ nixpkgs, nixpkgs-unstable, home-manager, flake-parts, ... }:
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
          import ./packages { pkgs = prev; }
        )
      ]; 
    };
    registry = _: {
      nix.registry = { #def.registry
        nixpkgs.flake = inputs.nixpkgs;
        nixpkgs-unstable.flake = inputs.nixpkgs-unstable;
      };
    };
      
    nixosSystem = { name, system, users, sysmodules ? [] }: #def.nixosSystem
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          packages
          registry
          ./modules
          ./machines/${name}/configuration.nix #def.machineConfig
          ./machines/${name}/hardware-configuration.nix
          ({config, ...}: {
            nixpkgs.overlays = [
              (final: prev: {
                unstable = import nixpkgs-unstable { #def.unstable
                  inherit system;
                  config.allowUnfreePredicate = config.nixpkgs.config.allowUnfreePredicate; 
                };
              })
            ];
          })
          home-manager.nixosModules.home-manager
          {
            home-manager.users = users;  #ref.hmUsers

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ] ++ sysmodules;
      };
  in
  flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" "aarch64-linux" ];

    perSystem = { pkgs, system, ... }: {
      # A shell interface with useful tools for modifying and realizing mynix
      devShells.default = pkgs.mkShell{ #def.devShell
        packages = with pkgs; [
          #def.buildsys
          (writers.writeBashBin "buildsys" ''
            set -e

            function verify_me() {
              read -p "$1 " choice
              case "''${choice,,}" in 
                y|yes ) echo "yes";;
                * ) echo "no";;
              esac
            }

            nixos-rebuild build --flake . --show-trace
            ${lib.getExe pkgs.nvd} diff /run/current-system result

            if [[ "yes" == $(verify_me "Switch?") ]]; then
              sudo nix-env -p /nix/var/nix/profiles/system --set ./result
              sudo result/bin/switch-to-configuration switch
              unlink result
            fi
          '')
          #def.updatesys
          (writers.writeBashBin "updatesys" ''
            set -e

            nix flake update
          '')
        ];

        shellHook = ''
          echo
          echo "================= mYniX ================="
          echo '- `buildsys`: Build, review, and apply current host'
          echo '- `updatesys`: Update the flake.lock'
          echo
        '';
      };
    };

    flake.nixosConfigurations = { #def.nixosConfigurations

      bones = nixosSystem {
        name = "bones";
        system = "x86_64-linux";
        users = { #def.hmUsers
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
        sysmodules = [ #ref.sysmodules
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
