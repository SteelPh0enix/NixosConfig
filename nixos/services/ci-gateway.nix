# Everything a CI job can reach: caddy adds the inference Bearer key, squid fetches by domain
# and logs it.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  # The key stays off the command line: a credential, expanded into the Caddyfile at load time.
  serve = pkgs.writeShellScript "ci-gateway-serve" ''
    set -euo pipefail
    LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/api-key")"
    export LLM_API_KEY
    exec ${lib.getExe pkgs.caddy} run --config ${caddyfile} --adapter caddyfile
  '';

  caddyfile = pkgs.writeText "ci-gateway-Caddyfile" ''
    {
      admin off
      auto_https off
    }

    # The engines' Bearer key is attached here, so a job needs none. `bind` pins the listener
    # to the bridge; a site address alone would listen on every interface and still serve TLS.
    http://:${toString settings.ciLlmPort} {
      bind ${settings.ciGateway}
      reverse_proxy 127.0.0.1:${toString settings.llmPort} {
        header_up Authorization "Bearer {$LLM_API_KEY}"
      }
    }
  '';

  # Exact hostnames: squid covers subdomains only with a leading dot.
  fetchDomains = [
    "cache.nixos.org"
    "releases.nixos.org"
    "github.com"
    "api.github.com"
    "codeload.github.com"
    "objects.githubusercontent.com"
    "index.crates.io"
    "static.crates.io"
    "registry.npmjs.org"
    "pypi.org"
    "files.pythonhosted.org"
  ];
in
{
  systemd.services.ci-gateway = {
    description = "CI service gateway (${settings.ciGateway}:${toString settings.ciLlmPort} -> 127.0.0.1:${toString settings.llmPort})";
    documentation = [ "https://caddyserver.com/docs/caddyfile" ];
    wantedBy = [ "multi-user.target" ];
    # The address it binds exists only once ci-network has created the bridge.
    after = [
      "ci-network.service"
      "network-online.target"
    ];
    wants = [
      "ci-network.service"
      "network-online.target"
    ];
    serviceConfig = {
      ExecStart = serve;
      LoadCredential = "api-key:${settings.llmApiKeyFile}";

      # caddy with `admin off` writes nothing; keep its XDG dirs in the private /tmp anyway.
      DynamicUser = true;
      Environment = [
        "XDG_DATA_HOME=/tmp"
        "XDG_CACHE_HOME=/tmp"
      ];
      Restart = "on-failure";
      RestartSec = 5;

      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      PrivateIPC = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      # AF_NETLINK stays: libc getifaddrs() while opening the listener.
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      LockPersonality = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectProc = "invisible";
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = true;
      UMask = "0077";
    };
  };

  # extraConfig lands before squid's `allow localnet` tail; the explicit deny keeps the bridge
  # out of that default.
  services.squid = {
    enable = true;
    proxyAddress = settings.ciGateway;
    proxyPort = settings.ciProxyPort;
    extraConfig = ''
      acl ci_jobs src ${settings.ciSubnet}
      acl ci_fetch dstdomain ${lib.concatStringsSep " " fetchDomains}
      http_access allow ci_jobs ci_fetch
      http_access deny ci_jobs
    '';
  };

  # squid binds the bridge address too, so it waits for the same unit.
  systemd.services.squid = {
    after = [ "ci-network.service" ];
    wants = [ "ci-network.service" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
