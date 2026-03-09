# Ceph distributed storage for seed cluster.
#
# NixOS runs the daemons; initial cluster bootstrap is imperative.
# See docs/rebuild.md for bootstrap procedure.
#
# Per-node config required:
#   services.ceph.mon.daemons = [ "seed-dfw-X" ];
#   services.ceph.mgr.daemons = [ "seed-dfw-X" ];
#   services.ceph.osd.daemons = [ "0" ];  # OSD ID assigned by ceph-volume
{ config, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.ceph ];

  services.ceph = {
    enable = true;
    global = {
      fsid = "c62ac465-94a6-496d-ba9f-fb1a62c6d2fb";
      monHost = "216.128.140.15,104.238.146.15,45.76.239.250";
      clusterNetwork = "10.42.0.0/16";
      publicNetwork = "216.128.140.0/23,104.238.146.0/23";
    };
    mon = {
      enable = true;
      daemons = [ config.networking.hostName ];
    };
    mgr = {
      enable = true;
      daemons = [ config.networking.hostName ];
    };
    osd = {
      # OSD IDs are assigned by ceph-volume during bootstrap.
      # Each node gets one OSD on /dev/sdb with dmcrypt.
      # After bootstrap: set enable = true and daemons = [ "0" ] (or assigned ID).
      enable = false;
      daemons = [];
    };
  };

  # Kernel modules for Ceph RBD (block device) access
  boot.kernelModules = [ "rbd" "ceph" ];

  # Ceph ports: mon (3300, 6789), OSD/MDS/MGR (6800-7568)
  networking.firewall.allowedTCPPortRanges = [
    { from = 3300; to = 3300; }
    { from = 6789; to = 6789; }
    { from = 6800; to = 7568; }
  ];
}
