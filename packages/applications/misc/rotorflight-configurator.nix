{
  lib,
  stdenv,
  fetchurl,
  unzip,
  makeDesktopItem,
  wrapGAppsHook3,
  unstable,
  #gsettings-desktop-schemas,
  #gtk3,
}:

let
  pname = "rotorflight-configurator";
  desktopItem = makeDesktopItem {
    name = pname;
    exec = pname;
    icon = pname;
    comment = "rotorflight configuration tool";
    desktopName = "Rotorflight Configurator";
    genericName = "Flight controller configuration tool";
  };
in
stdenv.mkDerivation rec {
  inherit pname;
  version = "2.2.1";
  src = fetchurl {
    url = "https://github.com/rotorflight/${pname}/releases/download/release%2F${version}/${pname}_${version}_linux_x86_64.tar.xz";
    sha256 = "sha256-870D2qXNQ5a4hf+rIr9TbneSOIjPmg/insR9mznOD14=";
  };

  nativeBuildInputs = [
    wrapGAppsHook3
    unzip
  ];

  buildInputs = [ ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin \
             $out/opt/${pname}

    cp -a ./package.nw/. $out/opt/${pname}/
    install -m 444 -D icon/bf_icon_128.png $out/share/icons/hicolor/128x128/apps/${pname}.png
    cp -a ${desktopItem}/share/applications $out/share/

    makeWrapper ${unstable.nwjs}/bin/nw $out/bin/${pname} --add-flags $out/opt/${pname}
    runHook postInstall
  '';

  meta = with lib; {
    description = "Rotorflight flight control system configuration tool";
    mainProgram = "rotorflight-configurator";
    longDescription = ''
      A crossplatform configuration tool for the Rotorflight flight control system.
    '';
    homepage = "https://www.rotorflight.org/";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.gpl3;
    maintainers = [];
    platforms = platforms.linux;
  };
}
