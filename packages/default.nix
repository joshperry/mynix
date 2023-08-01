{ pkgs }: {
  drata = pkgs.callPackage ./tools/security/drata.nix {};
}
