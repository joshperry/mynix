{
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
  writeShellScriptBin,
  runCommand,
}:

let
  name = "cura";
  version = "5.11.0";
  src = fetchurl {
    url = "https://github.com/Ultimaker/Cura/releases/download/${version}/UltiMaker-Cura-${version}-linux-X64.AppImage";
    hash = "sha256-us375gxVrGqGem2Et2VNRm6T389JxzPm1TScerlia9k=";
  };

  desktopItem = makeDesktopItem {
    inherit name;
    exec = name;
    icon = "Cura";
    comment = "Ultimaker Cura 3D Printer slicer";
    desktopName = "Cura";
    genericName = "3D printer slicer";
  };

  cura5 = appimageTools.wrapType2 rec {
    pname = name;
    inherit version src;

    extraInstallCommands =
      let
        appimageContents = appimageTools.extractType2 { pname = name; inherit version src; };
      in
        ''
          mkdir -p $out/share/pixmaps
          ln -s ${desktopItem}/share/applications $out/share/
          cp ${appimageContents}/cura-icon.png $out/share/pixmaps/Cura.png
        '';

    extraPkgs = pkgs: with pkgs; [ ];

    meta = with lib; {
      description = "3D printer / slicing GUI built on top of the Uranium framework";
      homepage = "https://github.com/Ultimaker/Cura";
      license = licenses.lgpl3Plus;
      platforms = platforms.linux;
      maintainers = with maintainers; [ abbradar ];
    };
  };
  wrapper = writeShellScriptBin "cura" ''
    # AppImage version of Cura loses current working directory and treats all paths relative to $HOME.
    # So we convert each of the files passed as argument to an absolute path.
    # This fixes use cases like `cd /path/to/my/files; cura mymodel.stl anothermodel.stl`.
    args=()
    for a in "$@"; do
      if [ -e "$a" ]; then
        a="$(realpath "$a")"
      fi
      args+=("$a")
    done
    exec "${cura5}/bin/cura" "''${args[@]}"
  '';
in
runCommand "cura-${version}" { meta = cura5.meta; } ''
  mkdir -p $out/bin $out/share/applications $out/share/pixmaps
  ln -s ${wrapper}/bin/cura $out/bin/cura
  ln -s ${desktopItem}/share/applications/* $out/share/applications/
  ln -s ${cura5}/share/pixmaps/* $out/share/pixmaps/
''
