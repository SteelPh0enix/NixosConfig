# Forgejo creates the runner and hands out a persistent uuid + token. The uuid is an identifier;
# the token is a credential.
{
  lib,
  pkgs,
  settings,
  ...
}:
{
  services.forgejo-runner = {
    package = pkgs.forgejo-runner;
    instances.framework = {
      enable = true;
      settings = {
        runner = {
          labels = [
            "framework:docker://${settings.ciRunnerImage}"
            "nix-ci:docker://${settings.ciRunnerImage}"
          ];
          # No key here: the gateway adds the one the inference endpoint wants.
          # Nix's sandbox needs namespaces the job container refuses, and the container is the
          # isolation anyway.
          envs = {
            HTTP_PROXY = "http://${settings.ciGateway}:${toString settings.ciProxyPort}";
            HTTPS_PROXY = "http://${settings.ciGateway}:${toString settings.ciProxyPort}";
            http_proxy = "http://${settings.ciGateway}:${toString settings.ciProxyPort}";
            https_proxy = "http://${settings.ciGateway}:${toString settings.ciProxyPort}";
            NO_PROXY = "localhost,127.0.0.1,${settings.ciGateway},${settings.forgejoDomain}";
            LLM_BASE_URL = "http://${settings.ciGateway}:${toString settings.ciLlmPort}/v1";
            NIX_CONFIG = "sandbox = false";
          };
        };
        # Both the address and the port are written into ACTIONS_CACHE_URL.
        cache = {
          enabled = true;
          host = settings.ciGateway;
          proxy_port = settings.ciCachePort;
        };
        container = {
          network = settings.ciNetwork;
          # The empty default mounts /var/run/docker.sock, so the dash must stay; an empty
          # valid_volumes mounts nothing.
          docker_host = "-";
          privileged = false;
          valid_volumes = [ ];
          # A job on this bridge cannot resolve the server name in ACTIONS_RUNTIME_URL.
          options = "--add-host ${settings.forgejoDomain}:${settings.ciGateway}";
        };
        server.connections.framework = {
          url = "http://${settings.forgejoDomain}:${toString settings.forgejoPort}/";
          uuid = "f3c3c627-b658-4f9f-8eeb-2f129f3ac085";
        };
      };
      secrets.server.connections.framework.token_url = settings.ciRunnerTokenFile;
    };
  };

  # The module would use /var/lib/forgejo-runner; this box keeps it under /var/lib/ci-runner.
  systemd.services."forgejo-runner-framework" = {
    serviceConfig = {
      StateDirectory = lib.mkForce "ci-runner/framework";
      WorkingDirectory = lib.mkForce "/var/lib/ci-runner/framework";
    };
    environment.HOME = lib.mkForce "/var/lib/ci-runner/framework";
    wants = lib.mkAfter [
      "dns-ready.target"
      "forgejo.service"
      "ci-network.service"
      "ci-gateway.service"
      "squid.service"
    ];
    after = lib.mkAfter [
      "dns-ready.target"
      "forgejo.service"
      "ci-network.service"
      "ci-gateway.service"
      "squid.service"
    ];
  };

  # The actions cache never expires on its own.
  systemd.services."ci-runner-cache-prune" = {
    description = "Prune the CI runner's actions cache";
    path = with pkgs; [
      findutils
      coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      # One cache entry is a directory; the buckets themselves stay.
      ExecStart = [
        "find /var/lib/ci-runner/framework/.cache/act -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf -- {} +"
        "find /var/lib/ci-runner/framework/.cache/act -mindepth 2 -maxdepth 2 -type d -mtime +14 -exec rm -rf -- {} +"
      ];
    };
  };
}
