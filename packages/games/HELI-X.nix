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
  statedir = "$HOME/.local/share/HELI-X";
  # Map of static jar files for the classpath
  jars = {
    HeliX = [
      "HeliX/HeliX_VR"
    ];
    jme = [
      "jme3-core"
      "jme3-plugins"
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
      "j-ogg-all"
      "gson"
      "nifty-default-controls"
    ];
    jdom = [
      "jdom"
    ];
    javagamenetworking = [
      "jgn"
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
    "$PWD/libs/jme/styles.zip"
    # HeliX updates these jars itself, so they must be in mutable storage
    "${statedir}/libs/HeliX/HeliX10.jar"
    "${statedir}/libs/HeliX/Translation.jar"
    "${statedir}/libs/HeliX/Media.jar"
  ];
  # Builds the classpath
  jarpaths = builtins.concatStringsSep ":" (
    lib.attrsets.foldlAttrs (
      acc: dir: files: builtins.concatLists [
        acc
        (map (file: "$PWD/libs/" + dir + "/" + file + ".jar") files)
      ]
    ) jarexceptions jars
  );

  startupscript = writeScript "initHELI-X.sh" ''
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
    if [ -e "$statedir/libs/HeliX/HeliX10_new.jar" ]
    then
       if [ -e "$statedir/libs/HeliX/HeliX10_back.jar" ]
       then
          rm "$statedir/libs/HeliX/HeliX10_back.jar"
       fi
       cp "$statedir/libs/HeliX/HeliX10.jar" "$statedir/libs/HeliX/HeliX10_back.jar"
       rm "$statedir/libs/HeliX/HeliX10.jar"
       mv "$statedir/libs/HeliX/HeliX10_new.jar" "$statedir/libs/HeliX/HeliX10.jar"
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

    # The path to a JRE is provided as the first parameter to this init script
    "$1"/bin/java \
      -Djava.library.path=`pwd` \
      -DheliX.path.resources="$statedir/resources" \
      -DheliX.path.files="$statedir/files" \
      -Xms512m \
      --add-opens=java.base/jdk.internal.ref=ALL-UNNAMED \
      -Djdk.tls.client.protocols=TLSv1.2 \
      -classpath ${jarpaths} \
      HELIX
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
  name = "HELI-X";

  src = fetchurl {
    url = "https://www.heli-x.info/2565/HELI-X10.tar.gz";
    hash = "sha256-k0fJ5io/BjAL94sKSFMN9Xk8EA0I5Md0JADvvCy48vE=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
  ];

  buildInputs = [
    pkgs.temurin-jre-bin-11
    pkgs.makeWrapper
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    
    install -Dm444 -T runHeli-X.ico $out/share/icons/HELI-X.ico

    find . -maxdepth 1 -type f | xargs -I {} cp {} $out/
    cp -R {libs,resources} $out/

    makeWrapper ${startupscript} $out/bin/HELI-X --chdir $out --set LD_LIBRARY_PATH ${lib.makeLibraryPath runtimeLibs} --add-flags "${pkgs.temurin-jre-bin-11}"
    
    runHook postInstall
  '';

  autoPatchelfIgnoreMissingDeps = [
    "libwayland-client.so.0"
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "HELI-X";
      exec = "HELI-X";
      icon = "HELI-X";
      comment = "Professional R/C Flight Simulation";
      desktopName = "HELI-X";
      genericName = "Professional R/C Flight Simulation";
    })
  ];
}
