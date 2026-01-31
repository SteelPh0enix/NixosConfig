{
  lib,
  pkgs,
  nixpkgs-unstable,
  inputs,
  ...
}:
let
  pkgsUnstable = import nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };

  motdConfig = pkgs.writeText "rust-motd.kdl" ''
    global {
        version "1.0"
    }
    components {
        weather url="https://wttr.in/Fajslawice?1" timeout=30
        service-status {
            service display-name="Accounts" unit="accounts-daemon"
            service display-name="PiHole" unit="pihole"
            service display-name="Open WebUI" unit="open-webui"
            service display-name="LanCache" unit="lancache"
            service display-name="Jellyfin" unit="jellyfin"
        }
        uptime prefix="Uptime"
        filesystems {
            filesystem name="root" mount-point="/"
            filesystem name="home" mount-point="/home"
        }
        memory swap-pos="beside"
        load-avg format="Load (1, 5, 15 min.): {one:.02}, {five:.02}, {fifteen:.02}"
        last-run
    }
  '';
in
{
  services.printing.enable = true;
  services.blueman.enable = true;
  services.thermald.enable = true;

  services.openssh = {
    enable = true;
    ports = [ 22137 ];
    openFirewall = true;
    settings = {
      X11Forwarding = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [
        "steelph0enix"
        "quake"
        "gitea"
      ];
      LogLevel = "VERBOSE";
      MaxAuthTries = 10;
    };
  };

  imports = [ inputs.ucodenix.nixosModules.default ];
  services.ucodenix = {
    enable = true;
    cpuModelId = "00B70F00";
  };

  services.gvfs = {
    enable = true;
    package = lib.mkForce pkgs.gnome.gvfs;
  };

  services.tuned = {
    enable = true;
    settings = {
      daemon = true;
      dynamic_tuning = true;
      recommend_command = true;
    };
  };

  services.watchdogd = {
    enable = true;
    settings = {
      meminfo.enabled = true;
      filenr.enabled = true;
      loadavg.enabled = true;
    };
  };

  systemd.services."rust-motd" = {
    script = "${pkgsUnstable.rust-motd}/bin/rust-motd ${motdConfig} > /tmp/motd && cp /tmp/motd /etc/motd";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
  users.motdFile = "/etc/motd";

  services.jellyfin = {
    enable = true;
    package = pkgsUnstable.jellyfin;
    openFirewall = true;
    user = "jellyfin";
    group = "users";
  };

  services.qbittorrent = {
    enable = true;
    package = pkgsUnstable.qbittorrent-enhanced-nox;
    user = "qbittorrent";
    group = "users";
    openFirewall = true;
    webuiPort = 8888;
    extraArgs = [
      "--confirm-legal-notice"
      "--sequential"
      "--first-and-last"
      "--save-path=/mnt/NAS2/Torrents"
      "--add-stopped=false"
      "--skip-dialog=false"
    ];
  };

  services.jackett = {
    enable = true;
    package = pkgsUnstable.jackett;
    openFirewall = true;
    port = 8889;
  };

  services.flaresolverr = {
    enable = true;
    package = pkgsUnstable.flaresolverr;
    openFirewall = true;
    port = 8890;
  };

  services.gitea = {
    enable = true;
    package = pkgsUnstable.gitea;
    lfs.enable = true;
    appName = "RX-78-GITEA";
    user = "gitea";
    settings = {
      server = {
        PROTOCOL = "http";
        HTTP_PORT = 6969;
        SSH_PORT = 22137;
        DOMAIN = "steelph0enix.framework";
        PUBLIC_URL_DETECTION = "auto";
        OFFLINE_MODE = true;
        ENABLE_GZIP = true;
        LFS_START_SERVER = true;
      };
      "repository.signing" = {
        SIGNING_KEY = "/var/lib/gitea/.ssh/gitea-signing-key.pub";
        SIGNING_EMAIL = "phoenixpl@hotmail.com";
        SIGNING_NAME = "Gitea";
        SIGNING_FORMAT = "ssh";
        INITIAL_COMMIT = "always";
        CRUD_ACTIONS = "pubkey, parentsigned";
        WIKI = "pubkey";
        MERGES = "pubkey, basesigned, commitssigned";
      };
    };
  };

  services.gitea-actions-runner = {
    package = pkgsUnstable.gitea-actions-runner;
    instances."RX-78" = {
      name = "RX-78";
      enable = true;
      url = "http://127.0.0.1:6969/";
      tokenFile = "/home/gitea/runner-token";
      labels = [
        "framework"
      ];
    };
  };

  systemd.services."gitea-runner-RX-78" = {
    serviceConfig = {
      # Disable DynamicUser to allow adding the user to the 'docker' group
      DynamicUser = lib.mkForce false;
      User = "gitea-runner";
      Group = "gitea-runner";
      SupplementaryGroups = [ "docker" ];
    };
  };

  services.xrdp = {
    package = pkgsUnstable.xrdp;
    enable = true;
    openFirewall = true;
    port = 3389;
    audio = {
      package = pkgsUnstable.pulseaudio-module-xrdp;
      enable = true;
    };
    defaultWindowManager = "xfce4-session";
  };
}
