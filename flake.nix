{
  description = "NixOS configurations";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-25.11"; };
    nixpkgs-unstable = { url = "github:nixos/nixpkgs/nixos-unstable"; };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = { url = "github:nix-community/impermanence"; };
    flake-parts.url = "github:hercules-ci/flake-parts";
    nuketown = {
      url = "github:joshperry/nuketown/cloud-design";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.impermanence.follows = "impermanence";
    };
    couchmail = {
      url = "github:joshperry/couchmail";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, nuketown, couchmail, sops-nix, flake-parts, ... }:
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
    let
      targetSystem = nixpkgs.lib.nixosSystem {
        modules = [
          { nixpkgs.hostPlatform = system; }
          packages
          registry
          ./modules
          sops-nix.nixosModules.sops
          ./machines/${name}/configuration.nix #def.machineConfig
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

      installer =
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lib = pkgs.lib;
          flakeOutPaths =
            let
              collector =
                parent:
                map (
                  child:
                  [ child.outPath ] ++ (if child ? inputs && child.inputs != { } then (collector child) else [ ])
                ) (lib.attrValues parent.inputs);
            in
            lib.unique (lib.flatten (collector self));
          dependencies = [
            targetSystem.pkgs.stdenv.drvPath
            (targetSystem.pkgs.closureInfo { rootPaths = [ ]; }).drvPath

            # https://github.com/NixOS/nixpkgs/blob/f2fd33a198a58c4f3d53213f01432e4d88474956/nixos/modules/system/activation/top-level.nix#L342
            targetSystem.pkgs.perlPackages.ConfigIniFiles
            targetSystem.pkgs.perlPackages.FileSlurp

            targetSystem.config.system.build.toplevel
            targetSystem.config.system.build.diskoScript
            targetSystem.config.system.build.diskoScript.drvPath
          ] ++ flakeOutPaths;
          closureInfo = pkgs.closureInfo { rootPaths = dependencies; };

          installerSystem = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              registry
              ({ pkgs, lib, config, ... }: {

                environment.etc."install-closure".source = "${closureInfo}/store-paths";

                nix = {
                  settings.experimental-features = ["nix-command" "flakes"];
                  extraOptions = "experimental-features = nix-command flakes";
                };

                services = {
                  openssh.settings.PermitRootLogin = lib.mkForce "yes";
                };

                boot = {
                  kernelPackages = pkgs.linuxPackages_latest;
                  supportedFilesystems = lib.mkForce ["btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs"];
                };

                networking = {
                  hostName = name;
                };

                # gnome power settings do not turn off screen
                systemd = {
                  services.sshd.wantedBy = pkgs.lib.mkForce ["multi-user.target"];
                  targets = {
                    sleep.enable = false;
                    suspend.enable = false;
                    hibernate.enable = false;
                    hybrid-sleep.enable = false;
                  };
                };

                environment.systemPackages = with pkgs; [
                  (writeShellScriptBin "install-system" ''
                    set -e
                    
                    TARGET="${targetSystem.config.system.build.toplevel}"
                    HOSTNAME="${name}"
                    
                    echo "=== Installing NixOS: $HOSTNAME ==="
                    echo "Target closure: $TARGET"
                    echo ""
                    
                    exec ${pkgs.disko}/bin/disko-install --flake "${self}#${name}"

                    #echo "Partitioning disk..."
                    #${lib.getExe pkgs.disko} --flake ${self}#${name}
                    #
                    #echo "Installing system..."
                    #nixos-install --system "$TARGET" --no-root-passwd
                    
                    echo ""
                    echo "Done! You can reboot now."
                  '')
                ];

                environment.shellInit = ''
                  echo ""
                  echo "=== NixOS Installer for ${name} ==="
                  echo "Run: install-system"
                  echo ""
                '';

              })
            ];
          };

          isoImage = installerSystem.config.system.build.isoImage;
          isoScript = pkgs.writeShellScriptBin "write-iso" ''
            set -e
            
            ISO=$(ls "${isoImage}/iso/"*.iso)

            if [[ -z "$1" ]]; then
              echo "Usage: write-iso /dev/sdX"
              echo ""
              echo "Available block devices:"
              lsblk -d -o NAME,SIZE,MODEL | grep -v loop
              exit 1
            fi
            
            DEVICE="$1"
            
            if [[ ! -b "$DEVICE" ]]; then
              echo "Error: $DEVICE is not a block device"
              exit 1
            fi
            
            if mount | grep -q "$DEVICE"; then
              echo "Error: $DEVICE appears to be mounted"
              exit 1
            fi
            
            echo "Writing: $ISO"
            echo "To:      $DEVICE"
            echo ""
            read -p "This will ERASE $DEVICE. Continue? [y/N] " confirm
            [[ "$confirm" != [yY] ]] && exit 1
            
            ${pkgs.lib.getExe pkgs.pv} "$ISO" | sudo dd of="$DEVICE" bs=4M oflag=direct 2>/dev/null
            echo ""
            echo "Done! You can remove the device."
          '';
        in
        installerSystem // { inherit isoScript; };
    in
    targetSystem // { inherit installer; };
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
          #def.installer
          (writers.writeBashBin "flash-installer" ''
            set -e

            if [[ -z "$1" ]] || [[ -z "$2" ]]; then
              echo "Usage: flash-installer <hostname> /dev/sdX"
              echo ""
              echo "Available hosts:"
              ls -1 machines/
              echo ""
              echo "Available block devices:"
              lsblk -d -o NAME,SIZE,MODEL | grep -v loop
              exit 1
            fi

            if [[ ! -d "machines/$1" ]]; then
              echo "Error: machines/$1 does not exist"
              exit 1
            fi

            if [[ ! -b "$2" ]]; then
              echo "Error: $2 is not a block device"
              exit 1
            fi

            echo "Building and flashing installer for $1 to $2..."
            nix run .#nixosConfigurations.$1.installer.isoScript -- "$2"
          '')
          #def.cloud-create
          google-cloud-sdk
          (writers.writeBashBin "cloud-create" ''
            set -e

            HOSTNAME="''${1:-cloudtest}"
            ZONE="''${2:-us-west1-b}"
            MACHINE_TYPE="''${3:-e2-medium}"
            DISK_SIZE="''${4:-20GB}"

            if ! ${google-cloud-sdk}/bin/gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
              echo "Not authenticated. Run: gcloud auth login"
              exit 1
            fi

            echo "Creating GCE instance: $HOSTNAME"
            echo "  Zone: $ZONE"
            echo "  Type: $MACHINE_TYPE"
            echo "  Disk: $DISK_SIZE"
            echo ""

            ${google-cloud-sdk}/bin/gcloud compute instances create "$HOSTNAME" \
              --zone="$ZONE" \
              --machine-type="$MACHINE_TYPE" \
              --image-family=debian-12 \
              --image-project=debian-cloud \
              --boot-disk-size="$DISK_SIZE" \
              --metadata=enable-oslogin=TRUE

            echo ""
            IP=$(${google-cloud-sdk}/bin/gcloud compute instances describe "$HOSTNAME" \
              --zone="$ZONE" \
              --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
            echo "Instance ready: $IP"
            echo ""
            echo "Next: cloud-deploy $HOSTNAME $IP"
          '')
          #def.cloud-deploy
          (writers.writeBashBin "cloud-deploy" ''
            set -e

            HOSTNAME="''${1}"
            IP="''${2}"

            if [[ -z "$HOSTNAME" ]] || [[ -z "$IP" ]]; then
              echo "Usage: cloud-deploy <hostname> <ip>"
              echo ""
              echo "Deploys a nixosConfiguration to a running VM via nixos-anywhere."
              echo "The VM should be running any Linux distro with root SSH access."
              echo ""
              echo "Available cloud-ready hosts:"
              ls -1 machines/
              exit 1
            fi

            if [[ ! -d "machines/$HOSTNAME" ]]; then
              echo "Error: machines/$HOSTNAME does not exist"
              exit 1
            fi

            echo "Deploying .#$HOSTNAME to $IP via nixos-anywhere..."
            echo ""

            nix run github:nix-community/nixos-anywhere -- \
              --flake ".#$HOSTNAME" \
              "root@$IP"
          '')
          #def.cloud-ssh
          (writers.writeBashBin "cloud-ssh" ''
            HOSTNAME="''${1:-cloudtest}"
            ZONE="''${2:-us-west1-b}"
            USER="''${3:-josh}"

            IP=$(${google-cloud-sdk}/bin/gcloud compute instances describe "$HOSTNAME" \
              --zone="$ZONE" \
              --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)

            if [[ -z "$IP" ]]; then
              echo "Error: could not find instance $HOSTNAME in zone $ZONE"
              exit 1
            fi

            echo "Connecting to $HOSTNAME ($IP) as $USER..."
            exec ssh "$USER@$IP"
          '')
          #def.cloud-destroy
          (writers.writeBashBin "cloud-destroy" ''
            set -e

            HOSTNAME="''${1:-cloudtest}"
            ZONE="''${2:-us-west1-b}"

            echo "This will DELETE instance: $HOSTNAME (zone: $ZONE)"
            read -p "Continue? [y/N] " confirm
            [[ "''${confirm,,}" != y* ]] && exit 1

            ${google-cloud-sdk}/bin/gcloud compute instances delete "$HOSTNAME" \
              --zone="$ZONE" \
              --quiet

            echo "Instance $HOSTNAME deleted."
          '')
        ];

        shellHook = ''
          echo
          echo "================= mYniX ================="
          echo '- `buildsys`: Build, review, and apply current host'
          echo '- `updatesys`: Update the flake.lock'
          echo '- `flash-installer <machine> <usbdev>`: Create minimal installer ISO with prebuilt system and write it to USB'
          echo ""
          echo "Cloud:"
          echo '- `cloud-create [host] [zone] [type] [disk]`: Create a GCE VM'
          echo '- `cloud-deploy <host> <ip>`: Deploy NixOS config via nixos-anywhere'
          echo '- `cloud-ssh [host] [zone] [user]`: SSH into a GCE instance'
          echo '- `cloud-destroy [host] [zone]`: Tear down a GCE instance'
          echo
        '';
      };
    };

    flake.nixosSystem = nixosSystem;

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
        sysmodules = [
          couchmail.nixosModules.default
        ];
      };

      mantissa = nixosSystem {
        name = "mantissa";
        system = "x86_64-linux";
        users = {
          josh = import ./users/josh;
        };
      };

      mino = nixosSystem {
        name = "mino";
        system = "x86_64-linux";
        users = {
          josh = import ./users/josh/server.nix;
        };
        sysmodules = [
          inputs.disko.nixosModules.disko
          inputs.impermanence.nixosModules.impermanence
        ];
      };

      signi = nixosSystem {
        name = "signi";
        system = "x86_64-linux";
        users = {
          josh = { imports = [
            ./users/josh/machines/signi
            nuketown.homeManagerModules.approvalDaemon
            { nuketown.approvalDaemon.enable = true; }
          ]; };
          # ada removed — nuketown manages ada's home-manager
        };
        sysmodules = [ #ref.sysmodules
          inputs.impermanence.nixosModules.impermanence
          nuketown.nixosModules.default
        ];
      };

      cloudtest = nixosSystem {
        name = "cloudtest";
        system = "x86_64-linux";
        users = {
          josh = import ./users/josh/server.nix;
        };
        sysmodules = [
          inputs.disko.nixosModules.disko
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
