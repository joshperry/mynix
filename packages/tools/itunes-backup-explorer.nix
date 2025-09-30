{ lib, fetchFromGitHub, jre, makeWrapper, maven, libGL, gtk3, glib, xorg }:
let
  runtimeLibs = [
    libGL
    gtk3
    glib
    xorg.libXtst
    xorg.libXxf86vm
  ];
in maven.buildMavenPackage rec {
  pname = "itunes-backup-explorer";
  version = "v1.7";

  src = fetchFromGitHub {
    owner = "MaxiHuHe04";
    repo = pname;
    rev = "${version}";
    hash = "sha256-yUugd/rUNRnO3gGaeDWf470RTd9uz3lwHqYGMSGlRfM=";
  };

  mvnHash = "sha256-fB40gA8aVVdb13UAULlXRj3GTNAqKka6uCKWf2MtKUU=";

  buildInputs = [
    makeWrapper
  ];

  mvnParameters = lib.escapeShellArgs ["clean" "compile" "assembly:single" "-P !linux"];

  installPhase = ''
    mkdir -p $out/bin $out/share/itunes-backup-explorer
    install -Dm644 target/itunes-backup-explorer-*.jar $out/share/itunes-backup-explorer/app.jar

    makeWrapper ${jre}/bin/java $out/bin/itunes-backup-explorer \
      --set LD_LIBRARY_PATH ${lib.makeLibraryPath runtimeLibs} \
      --prefix XDG_DATA_DIRS : "${gtk3}/share/gsettings-schemas/${gtk3.name}" \
      --add-flags "-jar $out/share/itunes-backup-explorer/app.jar"
  '';

  meta = with lib; {
    description = "A graphical tool that can extract and replace files from encrypted and non-encrypted iOS backups";
    homepage = "https://github.com/MaxiHuHe04/itunes-backup-explorer";
    license = licenses.mit;
  };
}
