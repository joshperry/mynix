{ config, lib, pkgs, ... }:
# WebDAV for phone backups (Seedvault) at https://kago.6bit.com, LAN only.
# One login per device, each confined to /mnt/md0/bu/phone/<device>, so
# backups get bu's btrbk snapshots and are reachable over the bu Samba share.
# Passwords are bcrypt hashes; the plaintext lives only on the device:
#   printf %s "$pw" | mkpasswd -m bcrypt -R 10 -s
#
# TLS for kago.6bit.com, a public record pointing at kago's LAN address
# (10.0.2.12, reserved on mino). kago is behind Starlink CGNAT, so the cert
# comes by DNS-01 through liver's acme-dns: _acme-challenge.kago.6bit.com is a
# CNAME to kago.acme.6bit.com, and kago's acme-dns account (declared on liver)
# can only set that one TXT.
let
  domain = "kago.6bit.com";
  phone = "/mnt/md0/bu/phone";
  devices = {
    mars = "$2b$10$GLroRoxu7f6n5arpIU.d5ufbr9019Qh9/B3YlFMqro4LatD7mq.qG";
  };
in
{
  sops.secrets."acme-dns/key" = { };
  # lego's acme-dns account file. registration is off on liver, so lego must
  # find the account here or it fails trying to register one.
  sops.templates.acme-dns-accounts = {
    owner = "acme";
    content = builtins.toJSON {
      ${domain} = {
        username = "36a3fcf4-4967-4a17-95f8-6b9fbe02cd02";
        password = config.sops.placeholder."acme-dns/key";
        subdomain = "kago";
        fulldomain = "kago.acme.6bit.com";
        server_url = "https://acme.6bit.com";
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "josh@6bit.com";
    certs.${domain} = {
      dnsProvider = "acme-dns";
      environmentFile = pkgs.writeText "acme-dns-env" ''
        ACME_DNS_API_BASE=https://acme.6bit.com
        ACME_DNS_STORAGE_PATH=${config.sops.templates.acme-dns-accounts.path}
      '';
      group = "webdav";
      reloadServices = [ "webdav.service" ];
    };
  };

  services.webdav = {
    enable = true;
    settings = {
      address = "[::]";
      port = 443;
      tls = true;
      cert = "/var/lib/acme/${domain}/fullchain.pem";
      key = "/var/lib/acme/${domain}/key.pem";
      # Only the per-user directories are served.
      directory = "/var/empty";
      permissions = "none";
      users = lib.mapAttrsToList (name: hash: {
        username = name;
        password = "{bcrypt}${hash}";
        directory = "${phone}/${name}";
        permissions = "CRUD";
      }) devices;
    };
  };
  systemd.services.webdav = {
    wants = [ "acme-${domain}.service" ];
    after = [ "acme-${domain}.service" ];
    serviceConfig = {
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      SupplementaryGroups = [ "nas" ];
      UMask = "0007";
    };
  };
  networking.firewall.allowedTCPPorts = [ 443 ];

  # bu's default ACL makes new files other-rwx; phone/ drops other access and
  # passes that on. setgid keeps new files in nas, which josh (Samba) is in.
  systemd.tmpfiles.rules = lib.concatMap (dir: [
    "d ${dir} 2770 webdav nas -"
    "a+ ${dir} - - - - other::---,default:other::---"
  ]) ([ phone ] ++ map (name: "${phone}/${name}") (lib.attrNames devices));
}
