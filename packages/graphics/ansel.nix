{ lib
, stdenv
, fetchgit
, libsoup
, graphicsmagick
, json-glib
, wrapGAppsHook
, cairo
, cmake
, ninja
, curl
, perl
, llvmPackages_13
, desktop-file-utils
, exiv2
, glib
, glib-networking
, ilmbase
, gtk3
, intltool
, lcms2
, lensfun
, libX11
, libexif
, libgphoto2
, libjpeg
, libpng
, librsvg
, libtiff
, libjxl
, openexr_3
, osm-gps-map
, pkg-config
, sqlite
, libxslt
, openjpeg
, pugixml
, colord
, colord-gtk
, libwebp
, libsecret
, gnome
, SDL2
, ocl-icd
, pcre
, gtk-mac-integration
, isocodes
, llvmPackages
, gmic
, libavif
, icu
, jasper
, libheif
, libaom
, portmidi
, lua
}:

stdenv.mkDerivation {
  version = "0.0.0";
  pname = "ansel";

  src = fetchgit {
    url = "https://github.com/aurelienpierreeng/ansel.git";
    rev    = "f7669af89a71882ebad15982d698b8df7e6c6ce8";
    sha256 = "sha256-FI6dKUrmtTG7DIV0MmY6XdqlUpqdt7boKuXKU6CywjA=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [ cmake ninja llvmPackages_13.llvm pkg-config intltool perl desktop-file-utils wrapGAppsHook ]
    ++ lib.optionals stdenv.isDarwin [ llvmPackages_13.clang ];

  buildInputs = [
    cairo
    curl
    exiv2
    glib
    glib-networking
    gtk3
    ilmbase
    lcms2
    lensfun
    libexif
    libgphoto2
    libjpeg
    libpng
    librsvg
    libtiff
    libjxl
    openexr_3
    sqlite
    libxslt
    libsoup
    graphicsmagick
    json-glib
    openjpeg
    pugixml
    libwebp
    libsecret
    SDL2
    gnome.adwaita-icon-theme
    osm-gps-map
    pcre
    isocodes
    gmic
    libavif
    icu
    jasper
    libheif
    libaom
    portmidi
    lua
  ] ++ lib.optionals stdenv.isLinux [
    colord
    colord-gtk
    libX11
    ocl-icd
  ] ++ lib.optional stdenv.isDarwin gtk-mac-integration
  ++ lib.optional stdenv.cc.isClang llvmPackages.openmp;

  cmakeFlags = [
    "-DBUILD_USERMANUAL=False"
  ] ++ lib.optionals stdenv.isDarwin [
    "-DUSE_COLORD=OFF"
    "-DUSE_KWALLET=OFF"
  ];

  preFixup =
    let
      libPathEnvVar = if stdenv.isDarwin then "DYLD_LIBRARY_PATH" else "LD_LIBRARY_PATH";
      libPathPrefix = "$out/lib/ansel" + lib.optionalString stdenv.isLinux ":${ocl-icd}/lib";
    in
    ''
      for f in $out/share/ansel/kernels/*.cl; do
        sed -r "s|#include \"(.*)\"|#include \"$out/share/ansel/kernels/\1\"|g" -i "$f"
      done

      gappsWrapperArgs+=(
        --prefix ${libPathEnvVar} ":" "${libPathPrefix}"
      )
    '';

  meta = with lib; {
    description = "Virtual lighttable and darkroom for photographers";
    homepage = "https://ansel.photos/";
    license = licenses.gpl3Plus;
    platforms = platforms.linux ++ platforms.darwin;
    maintainers = with maintainers; [ goibhniu flosse mrVanDalo paperdigits freyacodes ];
  };
}
