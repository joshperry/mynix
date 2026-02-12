{
  imports = [
    ./security/drata.nix
    ./security/falcon-sensor
    (import ./security/fprintd-lidcheck.nix {})
    ./security/sudo-approval.nix
    ./security/sops-age-yubikey.nix
  ];
}
