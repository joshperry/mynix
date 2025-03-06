{ pkgs }: {
  drata = pkgs.callPackage ./tools/security/drata.nix {};
  ansel = pkgs.callPackage ./graphics/ansel.nix {};
  cura = pkgs.callPackage ./applications/misc/cura.nix {};
  HELI-X = pkgs.callPackage ./games/HELI-X.nix {};
}
