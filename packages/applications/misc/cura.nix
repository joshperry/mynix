{
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
  writeShellScriptBin,
}:

let
  name = "cura";
  version = "5.8.1";
  src = fetchurl {
    url = "https://github.com/Ultimaker/Cura/releases/download/${version}/UltiMaker-Cura-${version}-linux-X64.AppImage";
    hash = "sha256-VLd+V00LhRZYplZbKkEp4DXsqAhA9WLQhF933QAZRX0=";
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
    inherit name src;

    extraInstallCommands =
      let
        appimageContents = appimageTools.extractType2 { inherit name src; };
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
      maintainers = with maintainers; [ abbradar gebner ];
    };
  };
in
writeShellScriptBin "cura" ''
  # AppImage version of Cura loses current working directory and treats all paths relateive to $HOME.
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
''
