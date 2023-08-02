{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.programs.drata;
in
{
  options.programs.drata = {
    enable = mkEnableOption (mdDoc "Drata security scanning client");
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.drata ];
  };

}
