{ lib
, stdenv
, fetchFromGitHub
, buildGoModule
, cmake
, pkg-config
, go
, pidgin
, gdk-pixbuf
, opusfile
, libogg
}:

let
  pname = "purple-gowhatsapp";
  version = "1.22.0";

  src = fetchFromGitHub {
    owner = "hoehermann";
    repo = "purple-gowhatsapp";
    rev = "v${version}";
    hash = "sha256-tAvS/TzspyFXN5idc+i1MOBkVkAebQagdM9XbKSdh70=";
    fetchSubmodules = true;
  };

  goModules = (buildGoModule {
    pname = "${pname}-go-modules";
    inherit version src;
    vendorHash = "sha256-ATCjQ7s7NOvElANzIgFbYhoAQ6dUE6K3vsAuRTETEXc=";
    # We only want the vendor dir; skip the actual Go build (it's a c-archive
    # driven by CMake in the parent derivation).
    buildPhase = "true";
    checkPhase = "true";
    installPhase = "touch $out";
  }).goModules;
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ cmake pkg-config go ];
  buildInputs = [ pidgin gdk-pixbuf opusfile libogg ];

  # scripts/go.cmake runs `go mod tidy` to regenerate go.mod from go.mod.in;
  # that hits the network. go.mod is already in the source, so neutralize it.
  postPatch = ''
    substituteInPlace scripts/go.cmake \
      --replace-fail \
        'COMMAND ''${CMAKE_COMMAND} -E env GOPATH=''${GOPATH} ''${CMAKE_Go_COMPILER} mod tidy' \
        'COMMAND ''${CMAKE_COMMAND} -E true'
  '';

  preConfigure = ''
    export HOME=$TMPDIR
    cp -r ${goModules} vendor
    chmod -R u+w vendor
    export GOFLAGS="-mod=vendor"
    export GOPROXY=off
  '';

  cmakeFlags = [
    "-DPURPLE_PLUGIN_DIR=${placeholder "out"}/lib/purple-2"
    "-DPURPLE_DATA_DIR=${placeholder "out"}/share"
  ];

  meta = with lib; {
    description = "libpurple/Pidgin plugin for WhatsApp powered by whatsmeow";
    homepage = "https://github.com/hoehermann/purple-gowhatsapp";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
