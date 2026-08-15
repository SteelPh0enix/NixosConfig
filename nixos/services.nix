{
  config,
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
            service display-name="Web Extract" unit="web-extract"
            service display-name="Jellyfin" unit="jellyfin"
            service display-name="Forgejo" unit="forgejo"
            service display-name="Forgejo runner" unit="gitea-runner-framework"
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
        "forgejo"
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

  # --- Forgejo (replaces Gitea) ---
  services.forgejo = {
    enable = true;
    package = pkgs.forgejo; # 16.0.2
    lfs.enable = true;
    settings = {
      DEFAULT.APP_NAME = "RX-78-FORGEJO";
      server = {
        PROTOCOL = "http";
        HTTP_PORT = 6969;
        SSH_PORT = 22137; # displayed in clone URLs
        DOMAIN = "steelph0enix.framework";
        # ROOT_URL auto-computed as http://steelph0enix.framework:6969/
        OFFLINE_MODE = true;
        ENABLE_GZIP = true;
      };
      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "github";
      };
      packages = {
        ENABLED = true;
      };
      # not present in the Forgejo v16 config reference; harmless no-op, kept for parity
      "packages.container" = {
        ENABLED = true;
      };
      "repository.signing" = {
        FORMAT = "ssh";
        SIGNING_KEY = "/var/lib/forgejo/.ssh/forgejo-signing-key.pub";
        SIGNING_EMAIL = "phoenixpl@hotmail.com";
        SIGNING_NAME = "Forgejo";
        INITIAL_COMMIT = "always";
        CRUD_ACTIONS = "pubkey, parentsigned";
        WIKI = "pubkey";
        MERGES = "pubkey, basesigned, commitssigned";
      };
      service = {
        DISABLE_REGISTRATION = true;
      };
    };
  };

  systemd.services."forgejo" = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];
  };

  # --- Forgejo Actions runner ---
  # Since Forgejo 15 the one-time "runner registration token" flow is
  # deprecated (forgejo/forgejo#11516, #11650): the WebUI now creates the
  # runner directly and issues a persistent uuid + token pair that belongs
  # in the runner's config file (server.connections). The nixpkgs
  # gitea-actions-runner module still tries the deprecated
  # `forgejo-runner register --token` flow in its ExecStartPre, which fails
  # with "runner registration token not found". We therefore replace
  # ExecStartPre/ExecStart with a config-based setup that reads UUID= and
  # TOKEN= from the token file (kept out of git / the nix store).
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.framework = {
      name = "framework";
      enable = true;
      url = "http://steelph0enix.framework:6969/";
      tokenFile = "/home/forgejo-runner/runner-token";
      labels = [
        "framework:docker://ghcr.io/catthehacker/ubuntu:act-latest"
        "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-latest"
      ];
      settings = {
        runner = {
          labels = [
            "framework:docker://ghcr.io/catthehacker/ubuntu:act-latest"
            "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-latest"
          ];
        };
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

  systemd.services."gitea-runner-framework" =
    let
      frameworkCfg = config.services.gitea-actions-runner.instances.framework;
      # Same base config the module would generate (everything except the
      # server connection, which is appended at runtime from the token file).
      baseConfig = (pkgs.formats.yaml { }).
        generate "config.yaml" frameworkCfg.settings;
    in
    {
      wants = [ "dns-ready.target" "forgejo.service" ];
      after = [ "dns-ready.target" "forgejo.service" ];
      serviceConfig = {
        SupplementaryGroups = [ "docker" ];
        Restart = lib.mkForce "no";
        # Replaces the module's deprecated registration step.
        ExecStartPre = lib.mkForce [
          (pkgs.writeShellScript "forgejo-runner-prepare-config" ''
            set -euo pipefail
            # File must contain: UUID=<runner uuid> and TOKEN=<runner token>
            source /home/forgejo-runner/runner-token
            mkdir -p /var/lib/gitea-runner/framework
            {
              cat ${baseConfig}
              cat <<EOF
server:
  connections:
    framework:
      url: ${frameworkCfg.url}
      uuid: ${"$" + "{UUID}"}
      token: ${"$" + "{TOKEN}"}
EOF
            } > /var/lib/gitea-runner/framework/config.yaml
          '')
        ];
        ExecStart = lib.mkForce
          "${pkgs.forgejo-runner}/bin/forgejo-runner daemon --config /var/lib/gitea-runner/framework/config.yaml";
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

  services.tuned = {
    enable = true;
    ppdSupport = true;
    settings = {
      dynamic_tuning = true;
    };
  };
}
