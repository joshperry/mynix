{ lib
, stdenv
, fetchurl
, dpkg
, undmg
, makeWrapper
, nodePackages
, alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, curl
, dbus
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gtk3
, libGL
, libappindicator-gtk3
, libdrm
, libnotify
, libpulseaudio
, libuuid
, libxcb
, libxkbcommon
, libxshmfence
, mesa
, nspr
, nss
, pango
, pipewire
, systemd
, wayland
, xdg-utils
, xorg
}:

let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "drata does not support system: ${system}";

  pname = "drata";

  x86_64-linux-version = "3.4.1";
  x86_64-linux-sha256 = "sha256-DVxsTAiDVNbGQZTvWZkvcu6UxB9oWTXh1AmqE7NLqBs=";

  version = {
    x86_64-linux = x86_64-linux-version;
  }.${system} or throwSystem;

  src = let
    base = "https://cdn.drata.com/agent/dist";
  in {
    x86_64-linux = fetchurl {
      url = "${base}/linux/drata-agent-${version}.deb";
      sha256 = x86_64-linux-sha256;
    };
  }.${system} or throwSystem;

  meta = with lib; {
    description = "Drata Client";
    homepage = "https://drata.com";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
in
stdenv.mkDerivation rec {
  inherit pname version src meta;

  rpath = lib.makeLibraryPath [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    curl
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libGL
    libappindicator-gtk3
    libdrm
    libnotify
    libpulseaudio
    libuuid
    libxcb
    libxkbcommon
    mesa
    nspr
    nss
    pango
    pipewire
    stdenv.cc.cc
    systemd
    wayland
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
    xorg.libxkbfile
    xorg.libxshmfence
  ] + ":${stdenv.cc.cc.lib}/lib64";

  buildInputs = [
    gtk3 # needed for GSETTINGS_SCHEMAS_PATH
  ];

  nativeBuildInputs = [ dpkg makeWrapper nodePackages.asar ];

  dontUnpack = true;
  dontBuild = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    # Extract the deb
    dpkg -x $src .

    # Move contents to outdir
    mkdir -p $out
    mv usr/* $out

    mkdir -p $out/lib/drata
    mv opt/Drata\ Agent/* $out/lib/drata

    # Otherwise it looks "suspicious"
    chmod -R g-w $out

    for file in $(find $out -type f \( -perm /0111 -o -name \*.so\* \) ); do
      patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$file" || true
      patchelf --set-rpath ${rpath}:$out/lib/drata $file || true
    done

    # Create a startup wrapper.
    # Make xdg-open overrideable at runtime.
    makeWrapper $out/lib/drata/drata-agent $out/bin/drata-agent \
      --prefix XDG_DATA_DIRS : $GSETTINGS_SCHEMAS_PATH \
      --suffix PATH : ${lib.makeBinPath [xdg-utils]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer}}"


    # Fix the desktop link
    substituteInPlace $out/share/applications/drata-agent.desktop \
      --replace '"/opt/Drata Agent/drata-agent"' $out/bin/drata-agent

    runHook postInstall
  '';
}
