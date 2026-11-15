{ pkgs, lib, osConfig, ... }:
let
  # SteamVR's vrclient.so is a prebuilt binary that can't find its libs outside
  # the steam FHS env; point its rpath at the env's /usr/lib64 (what fixxr.sh
  # did by hand). Steam replaces the file on every SteamVR update, so a path
  # unit re-runs this whenever SteamVR's app manifest (appid 250820) changes.
  steamvrFixRpath = pkgs.writeShellScript "steamvr-fix-rpath" ''
    set -eu
    steamapps="$HOME/.local/share/Steam/steamapps"
    vrclient="$steamapps/common/SteamVR/bin/linux64/vrclient.so"
    rpath="${osConfig.programs.steam.package.fhsenv}/usr/lib64"

    # The manifest is rewritten repeatedly while an update downloads; only
    # patch when StateFlags (a bitmask) is fully installed (4), ignoring
    # update-waiting (2) and running (64): an update sits at 6 for days with
    # its files staged in steamapps/temp, and common/ is complete meanwhile.
    flags=$(${pkgs.gnused}/bin/sed -n 's/.*"StateFlags"[[:space:]]*"\([0-9]*\)".*/\1/p' \
      "$steamapps/appmanifest_250820.acf" 2>/dev/null || true)
    if [ $(( ''${flags:-0} & ~(2|64) )) -ne 4 ]; then
      echo "SteamVR StateFlags ''${flags:-missing}, not installed or mid-update; skipping"
      exit 0
    fi
    [ -e "$vrclient" ] || { echo "no $vrclient"; exit 0; }

    if [ "$(${pkgs.patchelf}/bin/patchelf --print-rpath "$vrclient")" = "$rpath" ]; then
      echo "vrclient.so rpath already set"
    else
      # patchelf truncates and rewrites the file in place, which would crash a
      # running SteamVR (it runs while flag 64 is set); patch a copy and
      # rename it over, so running processes keep the old inode.
      tmp="$vrclient.steamvr-fix-rpath.tmp"
      trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
      ${pkgs.coreutils}/bin/cp --preserve=mode "$vrclient" "$tmp"
      ${pkgs.patchelf}/bin/patchelf --set-rpath "$rpath" "$tmp"
      ${pkgs.coreutils}/bin/mv -f "$tmp" "$vrclient"
      echo "vrclient.so rpath set to $rpath"
    fi
  '';
in
{
  imports = [ ../.. ];

  home.packages = with pkgs; [
    (pidgin.override { plugins = [ mynix.purple-gowhatsapp ]; })

    ardour

    # LAN CA: issue/sign certs against the YubiKey-PIV CA. step-cli/-kms-plugin
    # for ad-hoc cert inspection; yubico-piv-tool to manage the PIV applet.
    mynix.lan-ca
    step-cli
    step-kms-plugin
    yubico-piv-tool
  ];

  # The YubiKey serves both GnuPG (sops-age, OpenPGP applet) and the LAN CA
  # (lan-ca, PIV applet). By default scdaemon grabs the card's CCID interface
  # exclusively, locking out step-kms-plugin's PIV/pcsc access. Route GnuPG
  # through pcscd in shared mode so both applets are usable concurrently.
  # signi-only: requires pcscd, which is enabled system-wide here but not on
  # josh's other hosts that share users/josh/cli.nix.
  #
  # disable-application piv: once the LAN CA was provisioned into PIV slot 9c,
  # scdaemon began auto-selecting the now-populated PIV app and shadowing the
  # OpenPGP app, which broke gpg/ssh signing ("added app 'piv'..." then
  # "smartcard signing failed: General error"). Tell scdaemon to ignore PIV so
  # it always uses OpenPGP. The CA is unaffected: lan-cert/step-kms-plugin reach
  # PIV directly over PCSC/PKCS#11 (libykcs11), never through scdaemon.
  programs.gpg.scdaemonSettings = {
    disable-ccid = true;
    pcsc-shared = true;
    disable-application = "piv";
  };

  # Patched gnupg for THIS agent only (no pkgs.gnupg overlay, so gnupg's many
  # dependents — kwallet/fwupd/flatpak/notmuch/... — are not force-rebuilt).
  # gpg-agent's agent_card_pksign hands the data-to-sign to scdaemon on a single
  # Assuan line and rejects input over ~476 bytes with GPG_ERR_GENERAL, unlike
  # agent_card_pkdecrypt which chunks via "SETDATA --append". That blocks YubiKey
  # SSH auth (Ed25519 OpenPGP key) to venus.lan: OpenSSH host-bound auth embeds
  # venus's CA-signed host cert, inflating the to-be-signed blob to ~681 bytes,
  # and pure EdDSA signs it verbatim — so the card is never even contacted
  # ("smartcard signing failed: General error"). The patch makes pksign chunk
  # SETDATA like pkdecrypt; scdaemon already accumulates --append (MAXLEN 4096)
  # and the T5682 extended-APDU path carries it to the card.
  #
  # Already fixed upstream by gnupg commit fe147645d (NIIBE Yutaka, 2024-12-05,
  # GnuPG-bug-id 7436) via the same prepare_setdata chunking — but only on the
  # 2.5.x dev series. nixpkgs keeps 2.4.x as the default (the 2.4.9->2.5.19 bump
  # PR #435641 was closed) and is adding 2.5 only as an opt-in experimental
  # package (PR #515601, attr gnupg_25_experimental). Drop this patch once that
  # lands, by pointing programs.gpg.package at pkgs.gnupg_25_experimental, or
  # whenever the default gnupg crosses >= 2.5.2.
  programs.gpg.package = pkgs.gnupg.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./gnupg-card-pksign-chunk.patch ];
  });

  # k3s rootless + nix-snapshotter (home-manager user services)
  virtualisation.containerd.rootless = {
    enable = false;
    nixSnapshotterIntegration = true;
  };
  services.nix-snapshotter.rootless.enable = false;
  services.k3s.rootless = {
    enable = false;
    snapshotter = "nix";
    setKubeConfig = true;
    setEmbeddedContainerd = true;
    extraFlags = [
      "--disable traefik"
      "--disable servicelb"
      "--disable metrics-server"
      "--write-kubeconfig-mode 644"
    ];
  };

  # Workaround: upstream k3s-rootless sets EnvironmentFile=null which
  # home-manager's systemd type rejects. Remove it when not set.
  systemd.user.services.k3s.Service.EnvironmentFile = lib.mkForce [];

  # Also runs at login, which picks up a steam package change from a switch.
  systemd.user.services.steamvr-fix-rpath = {
    Unit.Description = "Point SteamVR's vrclient.so rpath at the steam FHS env";
    Service = {
      Type = "oneshot";
      ExecStart = "${steamvrFixRpath}";
    };
    Install.WantedBy = [ "default.target" ];
  };
  systemd.user.paths.steamvr-fix-rpath = {
    Unit.Description = "Watch SteamVR's app manifest for updates";
    Path.PathChanged = "%h/.local/share/Steam/steamapps/appmanifest_250820.acf";
    Install.WantedBy = [ "default.target" ];
  };
}
