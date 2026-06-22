{ pkgs, lib, ... }:
{
  imports = [ ../.. ];

  home.packages = with pkgs; [
    (pidgin.override { plugins = [ mynix.purple-gowhatsapp ]; })

    # LAN CA: issue/sign certs against the YubiKey-PIV CA. step-cli/-kms-plugin
    # for ad-hoc cert inspection; yubico-piv-tool to manage the PIV applet.
    mynix.lan-ca
    step-cli
    step-kms-plugin
    yubico-piv-tool
  ];

  # The YubiKey serves both GnuPG (sops-age, OpenPGP applet) and the LAN CA
  # (lan-ca, PIV applet). By default scdaemon grabs the card's CCID interface
  # exclusively, locking out step-kms-plugin's PIV/pcsc access. Route GnuPG
  # through pcscd in shared mode so both applets are usable concurrently.
  # signi-only: requires pcscd, which is enabled system-wide here but not on
  # josh's other hosts that share users/josh/cli.nix.
  programs.gpg.scdaemonSettings = {
    disable-ccid = true;
    pcsc-shared = true;
  };

  # k3s rootless + nix-snapshotter (home-manager user services)
  virtualisation.containerd.rootless = {
    enable = false;
    nixSnapshotterIntegration = true;
  };
  services.nix-snapshotter.rootless.enable = false;
  services.k3s.rootless = {
    enable = false;
    snapshotter = "nix";
    setKubeConfig = true;
    setEmbeddedContainerd = true;
    extraFlags = [
      "--disable traefik"
      "--disable servicelb"
      "--disable metrics-server"
      "--write-kubeconfig-mode 644"
    ];
  };

  # Workaround: upstream k3s-rootless sets EnvironmentFile=null which
  # home-manager's systemd type rejects. Remove it when not set.
  systemd.user.services.k3s.Service.EnvironmentFile = lib.mkForce [];
}
