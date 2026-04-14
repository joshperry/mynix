{ mkSeed, name }:
mkSeed {
  inherit name;
  module = { pkgs, ... }: {
    seed.size = "xs";
    seed.expose.http.enable = true;
    services.nginx = {
      enable = true;
      virtualHosts.default.root = pkgs.writeTextDir "index.html" "hello from ${name}";
    };
  };
}
