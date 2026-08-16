{ pkgs, ... }:

let
  # The Grafana admin password and secret key live in gitignored files in
  # this repo (see .gitignore) and must NOT end up in the Nix store, so
  # Grafana's `file:` provider is used. The grafana.service runs with
  # ProtectHome=true (and /etc/nixos is a symlink into the user's home),
  # so a small oneshot unit installs root:grafana 0640 copies of the
  # secrets into /var/lib before the service starts.
  # Note: these are plain strings, NOT Nix path literals - the files are
  # gitignored and must not be touched during (pure) evaluation.
  adminPasswordTarget = "/var/lib/grafana-secrets/admin-password";
  secretKeyTarget = "/var/lib/grafana-secrets/secret-key";

  # Written by the llama-metrics-discover timer: a Prometheus file_sd file
  # listing the child llama-server instances the routers have spawned for
  # currently loaded models (their ports are random, so they must be
  # discovered at runtime).
  llamaTargetsFile = "/var/lib/llama-metrics/llama-targets.json";
in
{
  # -------------------------------------------------------------------
  # Prometheus. Localhost only - Grafana on the same host is the sole
  # consumer, so no firewall port is opened.
  #
  # The two llama-server instances run in multi-model router mode
  # (--models-max/--models-preset): their own /metrics endpoint is a proxy
  # that requires a ?model= parameter, so it cannot be scraped directly.
  # When a model is loaded, the router spawns a child llama-server on a
  # random port that serves plain /metrics. The llama-metrics-discover
  # timer queries each router's /models endpoint and writes the loaded
  # children into a file_sd file, which the llm-models job scrapes.
  # -------------------------------------------------------------------
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    globalConfig = {
      scrape_interval = "30s";
    };
    scrapeConfigs = [
      {
        # Per-model metrics, served by the children the routers spawn.
        # Labels come from the file_sd file: server=<router>, model=<name>
        # (dashboards use {{server}} in their legends).
        job_name = "llm-models";
        file_sd_configs = [
          {
            files = [ llamaTargetsFile ];
            refresh_interval = "30s";
          }
        ];
      }
      {
        # Router liveness: /health is served by the router itself (its
        # /metrics route is a proxy and would 400 on a plain scrape).
        job_name = "llm-routers";
        metrics_path = "/health";
        static_configs = [
          {
            targets = [ "127.0.0.1:51580" ];
            labels = { server = "llm-router"; };
          }
          {
            # Host networking mode, so the port is reachable on localhost
            targets = [ "127.0.0.1:51536" ];
            labels = { server = "llm-router-rocm"; };
          }
        ];
      }
    ];
  };

  # Refresh the file_sd targets every 15s so a newly loaded model is
  # scraped shortly after its child comes up (and disappears when the
  # model is unloaded).
  systemd.services.llama-metrics-discover = {
    description = "Discover loaded llama.cpp router models for Prometheus";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Invoke the Nix store python explicitly: the service runs with a
      # minimal PATH, so the script's #!/usr/bin/env python3 shebang would
      # not resolve.
      ExecStart = [
        "${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/llama-metrics"
        "${pkgs.python3}/bin/python3 ${./llama-targets-discover.py} ${llamaTargetsFile}"
      ];
    };
  };

  systemd.timers.llama-metrics-discover = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5s";
      OnUnitActiveSec = "15s";
      # systemd's default timer accuracy is 1min; lower it so the 15s
      # cadence is actually honored.
      AccuracySec = "1s";
    };
  };

  # Installs the admin password where the file: provider can read it.
  systemd.services.grafana-secrets = {
    description = "Install Grafana admin password for the file: provider";
    wantedBy = [ "grafana.service" ];
    before = [ "grafana.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Runs as root without sandboxing, so it can read the gitignored
      # secrets from the repo (/etc/nixos is a symlink to it).
      # NOTE: must be a list of commands. A multi-line string renders the
      # extra lines as bare unit lines (no "ExecStart=" prefix), which
      # systemd silently ignores with "Missing '='" - only the first line
      # would run.
      ExecStart = [
        "${pkgs.coreutils}/bin/install -d -m 0750 -o root -g grafana /var/lib/grafana-secrets"
        "${pkgs.coreutils}/bin/install -m 0640 -o root -g grafana /etc/nixos/secrets/grafana-admin-password ${adminPasswordTarget}"
        "${pkgs.coreutils}/bin/install -m 0640 -o root -g grafana /etc/nixos/secrets/grafana-secret-key ${secretKeyTarget}"
      ];
    };
  };

  # -------------------------------------------------------------------
  # Grafana: serves the llama.cpp monitoring dashboard on :51555.
  # -------------------------------------------------------------------
  services.grafana = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 51555;
      };
      security = {
        admin_user = "admin";
        # file: provider - the actual secrets stay on disk (gitignored),
        # only these path strings end up in the Nix store.
        admin_password = "\$__file\{${adminPasswordTarget}\}";
        secret_key = "\$__file\{${secretKeyTarget}\}";
      };
    };
    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:9090";
            isDefault = true;
            editable = true;
          }
        ];
      };
      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "llamacpp";
            folder = "LLM";
            type = "file";
            allowUiUpdates = true;
            options.path = "/etc/grafana/dashboards";
          }
        ];
      };
    };
  };

  environment.etc."grafana/dashboards/llamacpp.json".source = ./dashboards/llamacpp.json;
}
