{
  autoPatchelfHook,
  fetchurl,
  gtk3,
  stdenv,
}:
let
  pname = "HELI-X";
  version = "1044";
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/bitdump/BLHeli/releases/download/Rev32.10/BLHeliSuite32xLinux64_1044.zip";
    hash = "";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    gtk3
  ];

  installPhase = ''
    install -Dm755 BLHeliSuite32xl $out/bin
  '';
}
