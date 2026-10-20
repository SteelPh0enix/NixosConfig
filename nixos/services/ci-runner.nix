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
        runner.labels = [
          "framework:docker://ghcr.io/catthehacker/ubuntu:act-latest"
          "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-latest"
        ];
        container = {
          # Mount the host Docker socket, so that the 'docker' command inside the container
          # talks to the daemon on the host.
          valid_volumes = [ "/var/run/docker.sock" ];
          docker_host = "-";
          network = "host";
        };
        server.connections.framework = {
          url = "http://steelph0enix.framework:6969/";
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
    # The runner talks to the Forgejo instance on this box, so it waits for it and for DNS.
    wants = lib.mkAfter [
      "dns-ready.target"
      "forgejo.service"
    ];
    after = lib.mkAfter [
      "dns-ready.target"
      "forgejo.service"
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
