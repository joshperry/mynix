{
  autoPatchelfHook,
  buildEnv,
  buildPackages,
  fetchurl,
  glib,
  gtk3,
  hidapi,
  lib,
  libGL,
  makeDesktopItem,
  stdenv,
  systemd,
  udev,
  unzip,
}:
let
  pname = "blhelisuite32";
  version = "32.10";
  blEnv = buildEnv {
    name = "blheli-env";
    paths = [
      hidapi
      gtk3
      glib
      libGL
      udev
    ];

    extraOutputsToInstall = [ "lib" "out" ];
  };

  desktopItem = makeDesktopItem {
    name = pname;
    exec = pname;
    comment = "BLHeli32 Configuration UI";
    desktopName = "BLHeli Suite";
    genericName = "BLHeli32 Configuration UI";
  };
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/bitdump/BLHeli/releases/download/Rev32.10/BLHeliSuite32xLinux64_1044.zip";
    hash = "sha256-Fi/rMQz02/2QVTY32Q16DcJPWmeVcx+EjcN+meBxt14=";
  };

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    buildPackages.wrapGAppsHook3
  ];

  buildInputs = [
    blEnv
  ];
  appendRunpaths = map (pkg: (lib.getLib pkg) + "/lib") [ blEnv stdenv.cc.libc stdenv.cc.cc ];

  preFixup = ''
    gappsWrapperArgs+=(
      --set LD_LIBRARY_PATH ${lib.makeLibraryPath [blEnv]}
    )
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    install -Dm755 BLHeliSuite32xl $out/opt/BLHeliSuite32xl
    install -D BLHeli32DefaultsX.cfg $out/opt/BLHeli32DefaultsX.cfg
    cp -a Interfaces $out/opt/
    cp -a ${desktopItem}/share/applications $out/share/

    ln -s $out/opt/BLHeliSuite32xl $out/bin/blhelisuite32
    ln -s ${lib.getLib hidapi}/lib/libhidapi-hidraw.so $out/opt/libhidapi-hidraw.so

    runHook postInstall
  '';
}
