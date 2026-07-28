{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  motdConfig = pkgs.writeText "rust-motd.kdl" ''
    global {
        version "1.0"
    }
    components {
        weather url="https://wttr.in/Fajslawice?1" timeout=30
        service-status {
            service display-name="Accounts" unit="accounts-daemon"
            service display-name="PiHole" unit="pihole"
            service display-name="AnythingLLM" unit="anything-llm"
            service display-name="Hindsight" unit="hindsight"
            service display-name="TEI" unit="tei"
            service display-name="Jellyfin" unit="jellyfin"
            service display-name="Gitea" unit="gitea"
            service display-name="Gitea runner" unit="gitea-runner-framework"
            service display-name="XRDP" unit="xrdp"
        }
        uptime prefix="Uptime"
        filesystems {
            filesystem name="root" mount-point="/"
            filesystem name="home" mount-point="/home"
            filesystem name="NAS" mount-point="/mnt/NAS"
            filesystem name="NAS2" mount-point="/mnt/NAS2"
        }
        memory swap-pos="beside"
        load-avg format="Load (1, 5, 15 min.): {one:.02}, {five:.02}, {fifteen:.02}"
        last-run
    }
  '';
in
{
  # Create dns-ready.target for services that depend on DNS resolution
  systemd.targets."dns-ready" = {
    description = "DNS resolution ready";
    unitConfig = {
      Requires = "dns-ready-check.service";
      After = "dns-ready-check.service";
    };
  };

  # DNS readiness check service - ensures DNS is actually functional
  systemd.services."dns-ready-check" = {
    description = "DNS readiness check";
    after = [ "pihole.service" ];
    requires = [ "pihole.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      RemainAfterExit = true;
    };
    script = ''
      # Wait for DNS to be ready by testing resolution
      echo "Waiting for DNS to be ready..."

      # Try DNS resolution with retries
      max_attempts=30
      attempt=1

      while [ $attempt -le $max_attempts ]; do
        # Try to resolve steelph0enix.framework
        if ${pkgs.dig}/bin/dig @localhost steelph0enix.framework +time=1 +tries=1 >/dev/null 2>&1; then
          echo "DNS is ready! Resolved steelph0enix.framework successfully."
          exit 0
        fi

        echo "DNS not ready yet (attempt $attempt/$max_attempts)..."
        sleep 1
        attempt=$((attempt + 1))
      done

      echo "Failed to verify DNS readiness after $max_attempts attempts"
      exit 1
    '';
  };

  services.printing.enable = true;
  services.blueman.enable = true;

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

  services.watchdogd = {
    enable = true;
    settings = {
      meminfo.enabled = true;
      filenr.enabled = true;
      loadavg.enabled = true;
    };
  };

  systemd.services."rust-motd" = {
    script = "${pkgs.rust-motd}/bin/rust-motd ${motdConfig} > /tmp/motd && cp /tmp/motd /etc/motd";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
  users.motdFile = "/etc/motd";

  services.jellyfin = {
    enable = true;
    package = pkgs.jellyfin;
    openFirewall = true;
    user = "jellyfin";
    group = "users";
  };

  systemd.services."jellyfin" = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];
  };

  services.qbittorrent = {
    enable = true;
    package = pkgs.qbittorrent-enhanced-nox;
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

  systemd.services."qbittorrent" = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];
  };

  services.jackett = {
    enable = true;
    package = pkgs.jackett;
    openFirewall = true;
    port = 8889;
  };

  systemd.services."jackett" = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];
  };

  services.flaresolverr = {
    enable = true;
    package = pkgs.flaresolverr;
    openFirewall = true;
    port = 8890;
  };

  systemd.services."flaresolverr" = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];
  };

  services.gitea = {
    enable = true;
    package = pkgs.gitea;
    lfs.enable = true;
    appName = "RX-78-GITEA";
    user = "gitea";
    settings = {
      packages = {
        ENABLED = true;
      };
      "packages.container" = {
        ENABLED = true;
      };
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
      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "github";
      };
    };
  };

  systemd.services."gitea" = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];
  };

  services.gitea-actions-runner = {
    package = pkgs.gitea-actions-runner;
    instances.framework = {
      name = "framework";
      enable = true;
      url = "http://steelph0enix.framework:6969/";
      tokenFile = "/home/gitea/runner-token";
      labels = [
        "framework:docker://ghcr.io/catthehacker/ubuntu:act-latest"
        "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-latest"
      ];
      settings = {
        container = {
          # MOUNT THE HOST DOCKER SOCKET
          # This allows the 'docker' command inside the container
          # to talk to the actual Docker daemon on NixOS.
          valid_volumes = [ "/var/run/docker.sock" ];
          docker_host = "-";
          network = "host";
        };
      };
    };
  };

  systemd.services."gitea-runner-framework" = {
    wants = [ "dns-ready.target" "gitea.service" ];
    after = [ "dns-ready.target" "gitea.service" ];
    serviceConfig = {
      SupplementaryGroups = [ "docker" ];
      Restart = lib.mkForce "no";
    };
  };

  services.xrdp = {
    package = pkgs.xrdp;
    enable = true;
    openFirewall = true;
    port = 3389;
    audio = {
      package = pkgs.pulseaudio-module-xrdp;
      enable = true;
    };
    defaultWindowManager = "xfce4-session";
  };

  systemd.services."xrdp" = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];
  };
}
