{
  lib,
  stdenv,
  fetchurl,
  unzip,
  electron,
  musl,
  makeDesktopItem,
  autoPatchelfHook,
  makeWrapper,
}:

let
  pname = "inav-configurator";
  version = "9.0.0";

  icon = fetchurl {
    url = "https://raw.githubusercontent.com/iNavFlight/${pname}/${version}/images/inav_icon_128.png";
    sha256 = "sha256-/EMleYuNk6s3lg4wYwXGUSLbppgmXrdJZkUX9n8jBMU=";
  };

  desktopItem = makeDesktopItem {
    name = pname;
    exec = pname;
    inherit icon;
    comment = "INAV flight controller configuration tool";
    desktopName = "INAV Configurator";
    genericName = "Flight controller configuration tool";
    categories = [ "Utility" ];
  };
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/iNavFlight/${pname}/releases/download/${version}/INAV-Configurator_linux_x64_${version}.zip";
    sha256 = "sha256-n56QE0ZJ2slL0WZbnBl2pEgAUoDMuh467gWt+eRwa9c=";
  };

  nativeBuildInputs = [
    makeWrapper
    autoPatchelfHook
    unzip
  ];

  buildInputs = [
    musl
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin \
             $out/opt/${pname}

    cp -a ./resources/. $out/opt/${pname}/
    install -m 444 -D ${icon} $out/share/icons/hicolor/128x128/apps/${pname}.png
    cp -a ${desktopItem}/share/applications $out/share/

    makeWrapper ${electron}/bin/electron $out/bin/${pname} --add-flags "$out/opt/${pname}/app"
    runHook postInstall
  '';

  meta = with lib; {
    description = "INAV flight control system configuration tool";
    mainProgram = "inav-configurator";
    longDescription = ''
      A crossplatform configuration tool for the INAV flight control system.
    '';
    homepage = "https://inavflight.github.io/";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.gpl3;
    maintainers = [];
    platforms = platforms.linux;
  };
}
