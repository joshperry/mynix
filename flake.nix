{
  description = "Bones NixOS configuration";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-22.11"; };
    nixos-unstable = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, nixos-unstable, home-manager, ... }:
  let
    # Overlays-module makes "pkgs.unstable" available in modules
    unstableOverlay = final: prev: { unstable = import nixos-unstable { inherit (prev) system; }; };
    overlayModule = ({ config, pkgs, ... }: { nixpkgs.overlays = [ unstableOverlay ]; });
  in
  {
    nixosConfigurations = {

      bones = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          overlayModule
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
