{ buildVimPlugin, fetchFromGitHub, }:

buildVimPlugin {
  pname = "direnv.nvim";
  version = "2025-09-30";
  src = fetchFromGitHub {
    owner = "actionshrimp";
    repo = "direnv.nvim";
    rev = "8a6d69b3a21928d54228f921bdee92b6839f25a1";
    sha256 = "sha256-qx+mbZz2tzA8F7pEYD4eGjujvpPa4/KfO9M6oxKFnM0=";
  };
  meta.homepage = "https://github.com/direnv/direnv.nvim/";
  meta.hydraPlatforms = [ ];
}
