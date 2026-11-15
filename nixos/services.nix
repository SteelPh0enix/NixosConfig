{
  lib,
  pkgs,
  inputs,
  settings,
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
            service display-name="AdGuard Home" unit="adguardhome"
            service display-name="Jellyfin" unit="jellyfin"
            service display-name="Forgejo" unit="forgejo"
            service display-name="Forgejo runner" unit="forgejo-runner-framework"
            ${lib.optionalString settings.enableRdp "service display-name=\"XRDP\" unit=\"xrdp\"\n"}
            service display-name="SearXNG" unit="searx"
        }
        uptime prefix="Uptime"
        filesystems {
            filesystem name="root" mount-point="/"
            filesystem name="home" mount-point="/home"
            filesystem name="NAS" mount-point="${settings.nasPath}"
            filesystem name="NAS2" mount-point="${settings.nas2Path}"
        }
        memory swap-pos="beside"
        load-avg format="Load (1, 5, 15 min.): {one:.02}, {five:.02}, {fifteen:.02}"
        last-run
    }
  '';

  # Services that resolve names during startup wait for the check below.
  dnsWait = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];
  };
in
{
  systemd.targets."dns-ready" = {
    description = "DNS resolution ready";
    unitConfig = {
      Requires = "dns-ready-check.service";
      After = "dns-ready-check.service";
    };
  };

  # The probe asks a public name and insists on an answer: AdGuard serves custom rewrites even
  # while upstreams are dead, and dig exits 0 on SERVFAIL.
  systemd.services."dns-ready-check" = {
    description = "DNS readiness check";
    after = [ "adguardhome.service" ];
    requires = [ "adguardhome.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo "Waiting for DNS to be ready..."
      max_attempts=30
      attempt=1

      while [ $attempt -le $max_attempts ]; do
        if [ -n "$(${pkgs.dig}/bin/dig @127.0.0.1 example.com +time=2 +tries=1 +short 2>/dev/null)" ]; then
          echo "DNS is ready: example.com resolved."
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

  systemd.services.flaresolverr = dnsWait;
  systemd.services.forgejo = dnsWait;
  systemd.services.jackett = dnsWait;
  systemd.services.jellyfin = dnsWait;
  systemd.services.qbittorrent = dnsWait;
  systemd.services.searx = dnsWait;
  systemd.services.xrdp = lib.mkIf settings.enableRdp dnsWait;

  services.openssh = {
    enable = true;
    ports = [ settings.sshPort ];
    openFirewall = true;
    settings = {
      # COLORTERM carries WezTerm's truecolor hint.
      AcceptEnv = [
        "LANG"
        "LC_*"
        "COLORTERM"
      ];
      X11Forwarding = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [
        settings.userName
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

  services.gvfs.enable = true;

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
    };
  };
  users.motdFile = "/etc/motd";

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user = "jellyfin";
    group = "users";
  };

  services.qbittorrent = {
    enable = true;
    package = pkgs.qbittorrent-enhanced-nox;
    user = "qbittorrent";
    group = "users";
    openFirewall = true;
    webuiPort = settings.qbittorrentWebPort;
    extraArgs = [
      "--confirm-legal-notice"
      "--sequential"
      "--first-and-last"
      "--save-path=${settings.nas2Path}/Torrents"
      "--add-stopped=false"
      "--skip-dialog=false"
    ];
  };

  services.jackett = {
    enable = true;
    openFirewall = true;
    port = settings.jackettPort;
  };

  services.flaresolverr = {
    enable = true;
    openFirewall = true;
    port = settings.flaresolverrPort;
  };

  services.caddy.enable = true;

  services.forgejo = {
    enable = true;
    lfs.enable = true;
    # The module defaults to forgejo-lts, whose schema is older than this instance's database
    # (migrated to v17).
    package = pkgs.forgejo;
    settings = {
      DEFAULT.APP_NAME = "RX-78-FORGEJO";
      server = {
        PROTOCOL = "http";
        HTTP_PORT = settings.forgejoPort;
        SSH_PORT = settings.sshPort; # displayed in clone URLs
        DOMAIN = settings.forgejoDomain;
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

  services.xrdp = lib.mkIf settings.enableRdp {
    enable = true;
    port = settings.xrdpPort;
    openFirewall = true;
    defaultWindowManager = "xfce4-session";
  };

  # tuned owns the CPU governor. `accelerator-performance` is pinned, and `ppdSupport = false`
  # keeps tuned-ppd from moving off it.
  services.tuned = {
    enable = true;
    ppdSupport = false;
    settings.dynamic_tuning = true;
    recommend.accelerator-performance = { };
  };

  services.fwupd.enable = true;
}
