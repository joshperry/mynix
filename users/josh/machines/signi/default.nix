{ pkgs, lib, ... }:
{
  imports = [ ../.. ];

  # k3s rootless + nix-snapshotter (home-manager user services)
  virtualisation.containerd.rootless = {
    enable = true;
    nixSnapshotterIntegration = true;
  };
  services.nix-snapshotter.rootless.enable = true;
  services.k3s.rootless = {
    enable = true;
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
