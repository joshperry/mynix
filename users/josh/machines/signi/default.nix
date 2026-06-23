{ pkgs, lib, ... }:
{
  imports = [ ../.. ];

  home.packages = with pkgs; [
    (pidgin.override { plugins = [ mynix.purple-gowhatsapp ]; })

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
}
