{ config, pkgs, ... }:
let
  postBuildHook = pkgs.writeShellScript "upload-to-cache" ''
    set -eu
    set -f
    export AWS_SHARED_CREDENTIALS_FILE=${config.sops.templates."seed-s3-credentials".path}
    if [ -f ${config.sops.secrets."seed/cache-signing-key".path} ]; then
      ${pkgs.nix}/bin/nix store sign --key-file ${config.sops.secrets."seed/cache-signing-key".path} $OUT_PATHS
      ${pkgs.nix}/bin/nix copy --to 's3://seed-nix-cache?endpoint=atl2.vultrobjects.com&region=us-east-1' $OUT_PATHS
    fi
  '';
in {
  sops.secrets."seed/cache-signing-key" = {};
  sops.secrets."seed/s3-access-key" = {};
  sops.secrets."seed/s3-secret-key" = {};

  sops.templates."seed-s3-credentials".content = ''
    [default]
    aws_access_key_id=${config.sops.placeholder."seed/s3-access-key"}
    aws_secret_access_key=${config.sops.placeholder."seed/s3-secret-key"}
  '';

  nix.settings = {
    substituters = [ "https://atl2.vultrobjects.com/seed-nix-cache" ];
    trusted-public-keys = [ "seed-cache-1:HmHh2GMeZTBXufX8RRs30bBNVB75+QfkgFllazC365E=" ];
    post-build-hook = postBuildHook;
  };

  # nix-daemon needs AWS credentials for S3 access (substituter downloads + post-build-hook uploads)
  systemd.services.nix-daemon.environment.AWS_SHARED_CREDENTIALS_FILE =
    config.sops.templates."seed-s3-credentials".path;
}
