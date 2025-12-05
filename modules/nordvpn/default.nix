{ config, lib, pkgs, ... }:

let
  nordVpnPkg = pkgs.callPackage (
    { autoPatchelfHook, buildFHSEnvChroot, dpkg, fetchurl, lib, stdenv,
      sysctl, iptables, iproute2, procps, cacert, libnl, libcap_ng,
      sqlite, libxml2, libidn2, zlib, wireguard-tools }:

    let
      pname = "nordvpn";
      version = "4.2.3";

      nordVPNBase = stdenv.mkDerivation {
        inherit pname version;

        src = fetchurl {
          url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_4.2.3_amd64.deb";
          hash = "sha256-LcTQEqaP1+UeBxi+gqQAuQKKzVgzMWSb7rMEB6qc6hk=";
        };

        buildInputs = [ libxml2 libidn2 libnl sqlite libcap_ng ];
        nativeBuildInputs = [ dpkg autoPatchelfHook stdenv.cc.cc.lib ];

        dontConfigure = true;
        dontBuild = true;

        unpackPhase = ''
          runHook preUnpack
          dpkg --extract $src .
          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          mv usr/* $out/
          mv var/ $out/
          mv etc/ $out/
          runHook postInstall
        '';
      };

      nordVPNfhs = buildFHSEnvChroot {
        name = "nordvpnd";
        runScript = "nordvpnd";

        targetPkgs = pkgs: [
          sqlite
          nordVPNBase
          sysctl
          iptables
          iproute2
          procps
          cacert
          libnl
          libcap_ng
          libxml2
          libidn2
          zlib
          wireguard-tools
        ];
      };
    in stdenv.mkDerivation {
      inherit pname version;

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/share
        ln -s ${nordVPNBase}/bin/nordvpn $out/bin
        ln -s ${nordVPNfhs}/bin/nordvpnd $out/bin
        ln -s ${nordVPNBase}/share/* $out/share/
        ln -s ${nordVPNBase}/var $out/
        runHook postInstall
      '';

      meta = with lib; {
        description = "CLI client for NordVPN";
        homepage = "https://www.nordvpn.com";
        license = licenses.unfreeRedistributable;
        platforms = [ "x86_64-linux" ];
      };
    }
  ) {};
in

{
  options.services.nordvpn.enable = lib.mkEnableOption "NordVPN daemon";
  options.services.nordvpn.users = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Users allowed to access NordVPN (added to nordvpn group).";
  };


  config = lib.mkIf config.services.nordvpn.enable {
    environment.systemPackages = [ nordVpnPkg ];

    users.groups.nordvpn = { };
    users.groups.nordvpn.members = config.services.nordvpn.users;

    networking.firewall.checkReversePath = false;

    systemd.services.nordvpn = {
      description = "NordVPN Daemon";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = "${nordVpnPkg}/bin/nordvpnd";
        ExecStartPre = pkgs.writeShellScript "nordvpn-start" ''
          mkdir -m 700 -p /var/lib/nordvpn;
          if [ -z "$(ls -A /var/lib/nordvpn)" ]; then
            cp -r ${nordVpnPkg}/var/lib/nordvpn/* /var/lib/nordvpn;
          fi
        '';
        NonBlocking = true;
        KillMode = "process";
        Restart = "on-failure";
        RestartSec = 5;
        RuntimeDirectory = "nordvpn";
        RuntimeDirectoryMode = "0750";
        Group = "nordvpn";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
