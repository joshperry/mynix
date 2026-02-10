{
  lib,
  mkDerivation,
  fetchFromGitHub,
  cmake,
  pkg-config,
  gnuradio,
  limesuite,
  python,
  spdlog,
  gnuradioAtLeast,
}:

mkDerivation {
  pname = "gr-limesdr";
  version = "0-unstable-2024-XX-XX";  # update with actual commit date

  src = fetchFromGitHub {
    owner = "myriadrf";
    repo = "gr-limesdr";
    rev = "gr-3.10";  # or pin to specific commit hash
    hash = "";  # nix-prefetch-url --unpack
  };

  # Remove if 3.11 support lands, or adjust as needed
  disabled = gnuradioAtLeast "3.11";

  buildInputs = [
    limesuite
    spdlog
  ] ++ lib.optionals (gnuradio.hasFeature "python-support") [
    python.pkgs.numpy
    python.pkgs.pybind11
  ];

  nativeBuildInputs = [
    cmake
    pkg-config
  ] ++ lib.optionals (gnuradio.hasFeature "python-support") [
    python
    python.pkgs.mako
  ];

  cmakeFlags = [
    (lib.cmakeBool "ENABLE_PYTHON" (gnuradio.hasFeature "python-support"))
  ];

  meta = {
    description = "GNU Radio blocks for LimeSDR devices";
    homepage = "https://github.com/myriadrf/gr-limesdr";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];  # add yourself if you want
  };
}
