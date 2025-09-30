{
  lib,
  stdenv,
  fetchurl,
  makeDesktopItem,
  autoPatchelfHook,
  copyDesktopItems,
  writeScript,
  pkgs,
}:
let
  statedir = "$HOME/.local/share/HELI-X11";
  # Map of static jar files for the classpath
  jars = {
    HeliX = [
      "HeliX_VR"
    ];
    jme = [
      "jme3-core"
      "jme3-plugins"
      "jme3-plugins-json"
      "jme3-terrain"
      "jme3-desktop"
      "jme3-jogg"
      "jme3-lwjgl3"
      "jme3-effects"
      "lwjgl"
      "lwjgl-glfw"
      "lwjgl-opengl"
      "lwjgl-jemalloc"
      "lwjgl-openal"
      "lwjgl-openvr"
      "nifty"
      "jme3-niftygui"
      "xpp3"
      "jutils"
      "j-ogg-vorbis"
      "gson"
      "nifty-default-controls"
    ];
    jdom = [
      "jdom"
    ];
    javagamenetworking = [
      "jgn"
      "slf4j-api-2.0.16"
      "slf4j-simple-2.0.16"
      "commons-collections4-4.4"
    ];
    math = [
      "openmali"
    ];
    jSerial = [
      "jSerialComm-2.4.0"
    ];
  };

  jarexceptions = [
    # Not a jar
    "./libs/jme/styles.zip"
    # HeliX updates these jars itself, so they must be in mutable storage
    "${statedir}/libs/HeliX/HeliX11.jar"
    "${statedir}/libs/HeliX/Translation.jar"
    "${statedir}/libs/HeliX/Media.jar"
    "${statedir}/libs/HeliX/server.jar"
  ];
  # Builds the classpath
  jarpaths = builtins.concatStringsSep ":" (
    lib.attrsets.foldlAttrs (
      acc: dir: files: builtins.concatLists [
        acc
        (map (file: "./libs/" + dir + "/" + file + ".jar") files)
      ]
    ) jarexceptions jars
  );

  startupscript = writeScript "initHELI-X11.sh" ''
    # HeliX manages some of its own jar files and also needs somewhere to download content
    statedir="${statedir}"
    mkdir -p $statedir

    # If the state dirs don't exist, initialize them with files from the installation
    if [ ! -d "$statedir/libs" ]
    then
      mkdir -p "$statedir/libs"
      cp -R libs/HeliX "$statedir/libs/"
      chmod -R +rw "$statedir/libs"
    fi

    if [ ! -d "$statedir/resources" ]
    then
      cp -R resources "$statedir/"
      chmod -R +rw "$statedir/resources"
    fi

    # This logic is from the original startup script for handling downloads of updated jars
    if [ -e "$statedir/libs/HeliX/HeliX11_new.jar" ]
    then
       if [ -e "$statedir/libs/HeliX/HeliX11_back.jar" ]
       then
          rm "$statedir/libs/HeliX/HeliX11_back.jar"
       fi
       cp "$statedir/libs/HeliX/HeliX11.jar" "$statedir/libs/HeliX/HeliX11_back.jar"
       rm "$statedir/libs/HeliX/HeliX11.jar"
       mv "$statedir/libs/HeliX/HeliX11_new.jar" "$statedir/libs/HeliX/HeliX11.jar"
    fi

    if [ -e "$statedir/libs/HeliX/Translation_new.jar" ]
    then
       if [ -e "$statedir/libs/HeliX/Translation_back.jar" ]
       then
          rm "$statedir/libs/HeliX/Translation_back.jar"
       fi
       cp "$statedir/libs/HeliX/Translation.jar" "$statedir/libs/HeliX/Translation_back.jar"
       rm "$statedir/libs/HeliX/Translation.jar"
       mv "$statedir/libs/HeliX/Translation_new.jar" "$statedir/libs/HeliX/Translation.jar"
    fi

    if [ -e "$statedir/libs/HeliX/Media_new.jar" ]
    then
       if [ -e "$statedir/libs/HeliX/Media_back.jar" ]
       then
          rm "$statedir/libs/HeliX/Media_back.jar"
       fi
       cp "$statedir/libs/HeliX/Media.jar" "$statedir/libs/HeliX/Media_back.jar"
       rm "$statedir/libs/HeliX/Media_back.jar"
       mv "$statedir/libs/HeliX/Media_new.jar" "$statedir/libs/HeliX/Media.jar"
    fi

    if [ -e "$statedir/libs/HeliX/server_new.jar" ]
    then
       if [ -e "$statedir/libs/HeliX/server_back.jar" ]
       then
          rm "$statedir/libs/HeliX/server_back.jar"
       fi
       cp "$statedir/libs/HeliX/server.jar" "$statedir/libs/HeliX/server_back.jar"
       rm "$statedir/libs/HeliX/server_back.jar"
       mv "$statedir/libs/HeliX/server_new.jar" "$statedir/libs/HeliX/server.jar"
    fi

    echo ${jarpaths}
    echo

    # The path to a JRE is provided as the first parameter to this init script
    runpath=""'''"$1"'''"/bin/java \
      --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
      -XX:+UseParallelGC \
      -Xms1g \
      -Xmx4g \
      -XX:MaxGCPauseMillis=200 \
      -XX:ParallelGCThreads=20 \
      -XX:ConcGCThreads=5 \
      -XX:InitiatingHeapOccupancyPercent=70 \
      -DheliX.path.resources="'''"$statedir/resources"'''" \
      -DheliX.path.files="'''"$statedir/files"'''" \
      -DheliX.path.java="'''"$1/bin"'''" \
      -Xms512m \
      -Djdk.tls.client.protocols=TLSv1.2 \
      -Dorg.lwjgl.util.Debug=true \
      -Dorg.lwjgl.util.DebugLoader=true \
      -DheliX.terminal="'''"$TERMINAL_COMMAND $TERMINAL_OPTIONS"'''" \
      -classpath "'''":${jarpaths}"'''" \
      HELIX"

      echo $runpath
      echo
      $runpath
  '';

  runtimeLibs = [
    ## openal
    pkgs.alsa-lib
    pkgs.libjack2
    pkgs.libpulseaudio
    pkgs.pipewire

    ## glfw
    pkgs.libGL
    pkgs.xorg.libX11
    pkgs.xorg.libXcursor
    pkgs.xorg.libXinerama
    pkgs.xorg.libXrandr
    pkgs.xorg.libXi
  ];
in
stdenv.mkDerivation {
  name = "HELI-X11";

  src = fetchurl {
    url = "https://www.heli-x.info/2675/HELI-X11.tar.gz";
    hash = "sha256-O9vDYDAVnp5Jicm7e+Nn9z5oWWrQNuKqhrOpvYl2MMc=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
  ];

  buildInputs = [
    pkgs.libGL
    pkgs.temurin-jre-bin
    pkgs.makeWrapper
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    
    install -Dm444 -T runHELI-X.ico $out/share/icons/HELI-X.ico

    find . -maxdepth 1 -type f | xargs -I {} cp {} $out/
    cp -R {libs,resources} $out/

    makeWrapper ${startupscript} $out/bin/HELI-X11 --chdir $out --set LD_LIBRARY_PATH "${lib.makeLibraryPath runtimeLibs}" --add-flags "${pkgs.temurin-jre-bin}"
    
    runHook postInstall
  '';

  autoPatchelfIgnoreMissingDeps = [
    "libwayland-client.so.0"
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "HELI-X 11";
      exec = "HELI-X11";
      icon = "HELI-X";
      comment = "Professional R/C Flight Simulation";
      desktopName = "HELI-X 11";
      genericName = "Professional R/C Flight Simulation";
    })
  ];
}
