{ lib, buildNpmPackage, fetchFromGitHub, runCommand, xclip, makeWrapper }:

let
  gitSrc = fetchFromGitHub {
    owner = "gulp";
    repo = "cc-prism";
    rev = "4380709e7e9f8be77a6da7b76653b433c0785b67";
    hash = "sha256-W1S/EK/UqKxjrelhQIQDp8GgaTtiu/dnb6zl+tKLxKk=";
  };

  # Upstream doesn't ship a lock file; we generated one from their package.json
  src = runCommand "cc-prism-src" {} ''
    cp -r ${gitSrc} $out
    chmod -R u+w $out
    cp ${./cc-prism-package-lock.json} $out/package-lock.json
  '';

in buildNpmPackage {
  pname = "cc-prism";
  version = "0.1.2";

  inherit src;

  npmDepsHash = "sha256-92IWEdofLJAXLenfBupeNqMOaHoFptdRkjg1v5t+z3M=";

  # dist/ is pre-built in the repo
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  # clipboardy shells out to xclip on Linux
  postFixup = ''
    wrapProgram $out/bin/cc-prism \
      --prefix PATH : ${lib.makeBinPath [ xclip ]}
  '';

  meta = {
    description = "Convert Claude Code sessions to asciinema terminal recordings";
    homepage = "https://github.com/gulp/cc-prism";
    license = lib.licenses.mit;
    mainProgram = "cc-prism";
  };
}
