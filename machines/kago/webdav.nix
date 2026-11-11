{ config, pkgs, ... }:
# TLS for kago.6bit.com, a public record pointing at kago's LAN address
# (10.0.2.12, reserved on mino). kago is behind Starlink CGNAT, so the cert
# comes by DNS-01 through liver's acme-dns: _acme-challenge.kago.6bit.com is a
# CNAME to kago.acme.6bit.com, and kago's acme-dns account (declared on liver)
# can only set that one TXT.
let
  domain = "kago.6bit.com";
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
    };
  };
}
