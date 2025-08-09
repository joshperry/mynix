{ lib, stdenv }:

stdenv.mkDerivation {
  pname = "stm-dfu-udev-rules";
  version = "0-unstable-2025-08-08";

  src = [ ./stm-dfu.rules ];

  dontUnpack = true;

  installPhase = ''
    install -Dpm644 $src $out/lib/udev/rules.d/70-stm-dfu.rules
  '';

  meta = with lib; {
    homepage = "https://github.com/Josverl/mpflash/blob/main/docs/stm32_udev_rules.md";
    description = "udev rules that give NixOS users permission to communicate with STM32 DFU bootloader";
    platforms = platforms.linux;
    license = "unknown";
  };
}
