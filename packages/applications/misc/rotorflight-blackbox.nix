{ alsa-lib
, at-spi2-core
, atk
, autoPatchelfHook
, buildEnv
, buildPackages
, cairo
, cups
, dbus
, expat
, fetchurl
, ffmpeg
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gtk3
, lib
, libcap
, libdrm
, libGL
, libnotify
, libuuid
, libxcb
, libxkbcommon
, libgbm
, makeDesktopItem
, nspr
, nss
, pango
, sqlite
, stdenv
, systemd
, udev
, unzip
, xorg
}:

let
  nwEnv = buildEnv {
    name = "nwjs-env";
    paths = [
      alsa-lib
      at-spi2-core
      atk
      cairo
      cups
      dbus
      expat
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gtk3
      libcap
      libdrm
      libGL
      libnotify
      libxkbcommon
      libgbm
      nspr
      nss
      pango
      xorg.libX11
      xorg.libXScrnSaver
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXtst
      xorg.libxshmfence
      # libnw-specific (not chromium dependencies)
      ffmpeg
      libxcb
      # chromium runtime deps (dlopen’d)
      libuuid
      sqlite
      udev
    ];

    extraOutputsToInstall = [ "lib" "out" ];
  };

  desktopItem = makeDesktopItem {
    name = pname;
    exec = pname;
    icon = pname;
    comment = "rotorflight blackbox tool";
    desktopName = "Rotorflight Blackbox";
    genericName = "Flight controller blackbox log analyzer";
  };

  pname = "rotorflight-blackbox";
  version = "2.2.0";
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/rotorflight/${pname}/releases/download/release%2F${version}/${pname}_${version}_linux64.zip";
    sha256 = "sha256-Zblcan94kggnWMnrs7rI3OXKxHRZeIotoV4+9mRiu7c=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    unzip
    # override doesn't preserve splicing https://github.com/NixOS/nixpkgs/issues/132651
    # Has to use `makeShellWrapper` from `buildPackages` even though `makeShellWrapper` from the inputs is spliced because `propagatedBuildInputs` would pick the wrong one because of a different offset.
    (buildPackages.wrapGAppsHook3.override { makeWrapper = buildPackages.makeShellWrapper; })
  ];

  buildInputs = [ nwEnv ];
  appendRunpaths = map (pkg: (lib.getLib pkg) + "/lib") [ nwEnv stdenv.cc.libc stdenv.cc.cc ];

  preFixup = ''
    gappsWrapperArgs+=(
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
    )
  '';

  installPhase = ''
      runHook preInstall
      mkdir -p $out/bin \
               $out/opt/${pname}

      cp -a . $out/opt/${pname}
      install -m 444 -D icon/bf_icon_128.png $out/share/icons/hicolor/128x128/apps/${pname}.png
      cp -a ${desktopItem}/share/applications $out/share/

      ln -s $out/opt/${pname}/${pname} $out/bin
      ln -s ${lib.getLib systemd}/lib/libudev.so $out/opt/${pname}/libudev.so.0

      runHook postInstall
    '';

  meta = with lib; {
    description = "Rotorflight blackbox analysis tool";
    mainProgram = "rotorflight-blackbox";
    longDescription = ''
      Blackbox log analyzer for the Rotorflight flight control system.
    '';
    homepage = "https://www.rotorflight.org/";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.gpl3;
    maintainers = [];
    platforms = platforms.linux;
  };
}
