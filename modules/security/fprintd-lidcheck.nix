{ services ? [ "sudo" "swaylock" "login" ] }:

let
  serviceModule = { lib, ... }: {
    options = {
      enable = lib.mkEnableOption "lid check for this service" // { default = true; };
      orderOffset = lib.mkOption {
        type = lib.types.int;
        default = -10;
        description = "Order offset from fprintd rule";
      };
    };
  };

  defaultServices = builtins.listToAttrs (map (s: { name = s; value = { }; }) services);
in
{ config, pkgs, lib, ... }:

let
  cfg = config.security.pam.lidCheck;

  lidClosedCheck = pkgs.writeShellApplication {
    name = "lid-closed-check";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      if grep -q closed /proc/acpi/button/lid/LID0/state 2>/dev/null; then
        exit 0
      fi
      exit 1
    '';
  };
in
{
  options.security.pam.lidCheck = {
    enable = lib.mkEnableOption "skip fingerprint auth when laptop lid is closed";

    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule serviceModule);
      default = defaultServices;
      description = ''
        Per-service configuration. Available services are fixed at module import.
        Use this to disable specific services or adjust order offsets.
      '';
      example = lib.literalExpression ''
        {
          sudo.enable = false;
          login.orderOffset = -5;
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    security.pam.services = lib.listToAttrs (lib.filter (x: x != null) (map (serviceName:
      let
        svcCfg = cfg.services.${serviceName} or { enable = true; orderOffset = -10; };
      in
      if svcCfg.enable then {
        name = serviceName;
        value.rules.auth.lid-check = {
          enable = config.security.pam.services.${serviceName}.fprintAuth;
          control = "[success=1 default=ignore]";
          modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
          args = [ "quiet" "${lib.getExe lidClosedCheck}" ];
          order = config.security.pam.services.${serviceName}.rules.auth.fprintd.order + svcCfg.orderOffset;
        };
      }
      else null
    ) services));
  };
}
