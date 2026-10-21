{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  writeShellScript,
  imagemagick,
  temurin-jre-bin,

  # Runtime libraries. GLFW 3.4 and OpenAL resolve every windowing/audio
  # backend through dlopen at runtime, so autoPatchelf cannot wire them up —
  # the only lever is LD_LIBRARY_PATH.
  alsa-lib,
  libjack2,
  libpulseaudio,
  pipewire,
  libGL,
  libglvnd,
  libX11,
  libXcursor,
  libXinerama,
  libXrandr,
  libXi,
  libXext,
  libXrender,
  libXxf86vm,
  libxcb,
  wayland,
  libxkbcommon,
  libdecor,
}:
let
  pname = "HELI-X11";
  version = "11";
  jre = temurin-jre-bin;

  # X11 is GLFW's default backend; the Wayland set lets GLFW's native Wayland
  # path load instead of silently falling through to XWayland.
  runtimeLibs = [
    # OpenAL
    alsa-lib
    libjack2
    libpulseaudio
    pipewire
    # GLFW — X11 backend
    libGL
    libX11
    libXcursor
    libXinerama
    libXrandr
    libXi
    libXext
    libXrender
    libXxf86vm
    libxcb
    # GLFW — Wayland backend (libglvnd provides libEGL.so.1)
    wayland
    libxkbcommon
    libdecor
    libglvnd
  ];

  # The launcher is version-agnostic; the wrapper injects the store paths
  # (HELIX_HOME, HELIX_JRE, HELIX_VERSION) so this never has to be rebuilt when
  # they change.
  launcher = writeShellScript "heli-x11" ''
    set -euo pipefail

    # HELI-X updates four of its own jars in place and writes downloaded
    # content (models, scenes) back into resources/, so all mutable state lives
    # under the user's data dir, not the read-only store.
    statedir="''${XDG_DATA_HOME:-$HOME/.local/share}/HELI-X11"
    libdir="$statedir/libs/HeliX"

    # First-run seed ONLY. Once these exist we never touch them again: HELI-X
    # self-updates its own jars (the *_new.jar mechanism below) and downloads
    # content into resources/, and the user's settings/joystick/registration
    # live under here too. Never overwrite — that is what lets all of it persist
    # across package/version updates. A new major version ships as its own
    # package with its own state dir, exactly like HELI-X vs HELI-X11.
    if [ ! -e "$libdir/HeliX11.jar" ]; then
      mkdir -p "$statedir/libs"
      cp -R "$HELIX_HOME/libs/HeliX" "$statedir/libs/"
      chmod -R u+rwX "$statedir/libs/HeliX"
    fi
    if [ ! -d "$statedir/resources" ]; then
      cp -R "$HELIX_HOME/resources" "$statedir/resources"
      chmod -R u+rwX "$statedir/resources"
    fi
    mkdir -p "$statedir/files" "$statedir/data"

    # Apply any jar updates HELI-X downloaded on the previous run. Upstream's
    # own script copies then immediately rm's the rollback backup it just made;
    # this keeps <jar>_back.jar intact.
    for jar in HeliX11 Translation Media server; do
      if [ -e "$libdir/''${jar}_new.jar" ]; then
        mv -f "$libdir/$jar.jar" "$libdir/''${jar}_back.jar" 2>/dev/null || true
        mv -f "$libdir/''${jar}_new.jar" "$libdir/$jar.jar"
      fi
    done

    # Classpath mirrors upstream's runHELI-X.sh client launcher exactly. The
    # tarball also ships jme3-vr, lwjgl-openxr and vecmath (in jme/) plus
    # server.jar, none of which upstream's client launcher puts on the path —
    # they belong to the VR and dedicated-server entry points. We track
    # upstream's tested set rather than wildcard jme/*, because a dir/* wildcard
    # can't drop those extras and their effect on the client is untested (note
    # lwjgl-openvr IS kept — upstream keeps it; the rule is "match upstream", not
    # "exclude everything VR"). The four self-updating app jars come from
    # writable state; the rest are referenced from the store.
    classpath="$libdir/HeliX11.jar:$libdir/HeliX_VR.jar:$libdir/Translation.jar:$libdir/Media.jar"
    for j in jme3-core jme3-plugins jme3-plugins-json jme3-terrain jme3-desktop \
             jme3-jogg jme3-lwjgl3 jme3-effects lwjgl lwjgl-glfw lwjgl-opengl \
             lwjgl-jemalloc lwjgl-openal lwjgl-openvr nifty jme3-niftygui xpp3 \
             jutils j-ogg-vorbis gson nifty-default-controls; do
      classpath="$classpath:$HELIX_HOME/libs/jme/$j.jar"
    done
    classpath="$classpath:$HELIX_HOME/libs/jme/styles.zip"
    classpath="$classpath:$HELIX_HOME/libs/jdom/jdom.jar"
    classpath="$classpath:$HELIX_HOME/libs/javagamenetworking/jgn.jar"
    classpath="$classpath:$HELIX_HOME/libs/javagamenetworking/slf4j-api-2.0.16.jar"
    classpath="$classpath:$HELIX_HOME/libs/javagamenetworking/slf4j-simple-2.0.16.jar"
    classpath="$classpath:$HELIX_HOME/libs/javagamenetworking/commons-collections4-4.4.jar"
    classpath="$classpath:$HELIX_HOME/libs/math/openmali.jar"
    classpath="$classpath:$HELIX_HOME/libs/jSerial/jSerialComm-2.4.0.jar"

    debug=""
    if [ -n "''${HELIX_DEBUG:-}" ]; then
      debug="-Dorg.lwjgl.util.Debug=true -Dorg.lwjgl.util.DebugLoader=true"
    fi

    cd "$statedir"
    exec "$HELIX_JRE/bin/java" \
      --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
      -XX:+UseParallelGC \
      -Xms512m \
      -Xmx4g \
      -Djdk.tls.client.protocols=TLSv1.2 \
      -Dorg.lwjgl.librarypath="$HELIX_HOME" \
      -DheliX.path.resources="$statedir/resources" \
      -DheliX.path.files="$statedir/files" \
      -DheliX.path.java="$HELIX_JRE/bin" \
      -DheliX.terminal="''${TERMINAL_COMMAND:-} ''${TERMINAL_OPTIONS:-}" \
      $debug \
      -classpath "$classpath" \
      HELIX "$@"
  '';
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://www.heli-x.info/2675/HELI-X11.tar.gz";
    hash = "sha256-iPSnfKhxXOGZYkm0pdUgHVrO7IPWd/G+52yVuSxvNnU=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
    imagemagick
  ];

  # autoPatchelf resolves the natives' real NEEDED entries from here; the
  # dlopen'd backends are handled by LD_LIBRARY_PATH at runtime.
  buildInputs = runtimeLibs ++ [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    # App payload: LWJGL/OpenAL natives (top level) + libs + resources. The
    # bundled Java/ JRE is dropped in favour of nixpkgs' temurin-jre-bin.
    mkdir -p $out/share/heli-x
    cp *.so $out/share/heli-x/
    cp -R libs resources $out/share/heli-x/

    # Real PNG icon (frame 5 of the .ico is a 256x256 PNG) so desktops that
    # follow the XDG icon theme spec can actually find it.
    mkdir -p $out/share/icons/hicolor/256x256/apps
    magick "runHELI-X.ico[5]" $out/share/icons/hicolor/256x256/apps/HELI-X11.png

    makeWrapper ${launcher} $out/bin/HELI-X11 \
      --set HELIX_HOME $out/share/heli-x \
      --set HELIX_JRE ${jre} \
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath runtimeLibs}"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "HELI-X11";
      exec = "HELI-X11";
      icon = "HELI-X11";
      comment = "Professional R/C flight simulation";
      desktopName = "HELI-X 11";
      genericName = "R/C Flight Simulator";
      categories = [ "Game" "Simulation" ];
    })
  ];

  meta = {
    description = "Professional R/C flight simulator for helicopters and planes";
    homepage = "https://www.heli-x.info/";
    # Proprietary EULA: private use only, redistribution and modification
    # forbidden. Fetched straight from the vendor, never cached or redistributed.
    license = {
      shortName = "HELI-X-EULA";
      fullName = "HELI-X End User License Agreement";
      free = false;
      redistributable = false;
    };
    sourceProvenance = with lib.sourceTypes; [
      binaryNativeCode
      binaryBytecode
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "HELI-X11";
    maintainers = [ ];
  };
}
