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
in
{
  # -------------------------------------------------------------------
  # Prometheus: scrapes the /metrics endpoints of both llama-server
  # instances (both run with --metrics). Localhost only - Grafana on
  # the same host is the sole consumer, so no firewall port is opened.
  # -------------------------------------------------------------------
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    globalConfig = {
      scrape_interval = "30s";
    };
    scrapeConfigs = [
      {
        job_name = "llm-router";
        static_configs = [
          {
            targets = [ "127.0.0.1:51580" ];
            # Distinguishes the two servers in dashboards (legend: {{server}})
            labels = { server = "llm-router"; };
          }
        ];
      }
      {
        job_name = "llm-router-rocm";
        static_configs = [
          {
            # Host networking mode, so the port is reachable on localhost
            targets = [ "127.0.0.1:51536" ];
            labels = { server = "llm-router-rocm"; };
          }
        ];
      }
    ];
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
