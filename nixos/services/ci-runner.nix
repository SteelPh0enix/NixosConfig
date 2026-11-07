# The CI runner for Forgejo Actions. Since Forgejo 15 the one-time "runner registration
# token" flow is deprecated (forgejo/forgejo#11516, #11650): the WebUI creates the runner
# itself and hands out a persistent uuid + token pair, which belongs in the runner's config
# file under server.connections. The uuid is an identifier rather than a credential, so it
# sits here; the token comes in as a systemd credential and the runner reads it from there,
# so it never lands in a file on disk.
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
            # The same image, named for what it provides rather than for a distro: a
            # workflow that wants to say it needs this environment picks it, and
            # nothing behaves differently once it is scheduled.
            "nix-ci:docker://${settings.ciRunnerImage}"
          ];
          # Where a build finds the services it is allowed to use. No key among them -
          # the gateway adds the one the inference endpoint wants (ci-gateway.nix).
          # Nix's own sandbox needs namespaces this container will not hand out
          # (unshare and mount are refused by seccomp) and the container is the
          # isolation anyway, so saying it here keeps the warning out of every job log
          # and out of the workflow, which has to stay honest for whatever runner it
          # ends up on.
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
        # The job reaches the runner's cache over the gateway address: `host` is the
        # address written into ACTIONS_CACHE_URL and `proxy_port` the port it connects
        # to, so both have to be named. A cache the job cannot reach means every run
        # rebuilds the store, which is the memory spike AGENTS.md warns about.
        cache = {
          enabled = true;
          host = settings.ciGateway;
          proxy_port = settings.ciCachePort;
        };
        container = {
          network = settings.ciNetwork;
          # The empty default mounts /var/run/docker.sock into the job container, so
          # the dash has to stay written down. valid_volumes is the allowlist a
          # workflow's `volumes:` is checked against, and an empty one means nothing is
          # ever mounted - the socket included.
          docker_host = "-";
          privileged = false;
          valid_volumes = [ ];
          # The server's own name reaches the job inside ACTIONS_RUNTIME_URL, and a
          # container on this bridge has no way to resolve it, so it maps to the
          # gateway address - the answer the host's resolver gives for it too.
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

  # The module would put an instance's state in /var/lib/forgejo-runner/<name>; this box keeps
  # it under /var/lib/ci-runner, and the cache-prune service below looks there.
  systemd.services."forgejo-runner-framework" = {
    serviceConfig = {
      StateDirectory = lib.mkForce "ci-runner/framework";
      WorkingDirectory = lib.mkForce "/var/lib/ci-runner/framework";
    };
    environment.HOME = lib.mkForce "/var/lib/ci-runner/framework";
    # The runner talks to the Forgejo instance on this box and hands jobs to containers
    # on the bridge, so it waits for the instance and DNS, and for the bridge with its
    # two listeners, before it takes work.
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

  # The runner's actions cache never expires on its own: forgejo-runner knows only where
  # to put it, and every repository that caches something adds an entry - the mc-modpack nix store,
  # esquie's cargo registry and nix store, the checkout git caches. Fourteen days is long enough for
  # a cache to outlive a work cycle and short enough that the runner's disk stays reasonable; a miss
  # only costs a download.
  systemd.services."ci-runner-cache-prune" = {
    description = "Prune the CI runner's actions cache";
    path = with pkgs; [
      findutils
      coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      # One cache entry is a directory: the actions/cache blobs sit in the two-hex buckets, the
      # checkout action's git caches at the top level. The buckets themselves are left in place.
      ExecStart = [
        "find /var/lib/ci-runner/framework/.cache/act -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf -- {} +"
        "find /var/lib/ci-runner/framework/.cache/act -mindepth 2 -maxdepth 2 -type d -mtime +14 -exec rm -rf -- {} +"
      ];
    };
  };
}
