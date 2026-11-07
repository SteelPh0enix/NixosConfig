# The whole service surface a CI job has: with no route off its bridge except this
# gateway address, whatever listens here is everything a build can reach. Two
# listeners - caddy, which adds the inference endpoint's Bearer key so that no
# workflow, log or job environment carries one, and squid, which fetches by domain
# and writes down what it fetched.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  # The key must not land in the store: systemd hands it over as a credential and this
  # wrapper exports it as the variable the Caddyfile's {$LLM_API_KEY} placeholder
  # expands at load time, so the value stays off the process command line.
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

    # The OpenAI-compatible endpoint. The credential the engines on settings.llmPort
    # already require is attached here, so a job needs none of its own, and whichever
    # engine is up answers: gufo behind gufo-auth, or one of the llama.cpp builds.
    # The address goes in `bind`: a site address naming an address only matches the
    # Host header, leaving the port listening on every interface.
    :${toString settings.ciLlmPort} {
      bind ${settings.ciGateway}
      reverse_proxy 127.0.0.1:${toString settings.llmPort} {
        header_up Authorization "Bearer {$LLM_API_KEY}"
      }
    }
  '';

  # What a build may fetch; everything else is refused, so this is the list a project
  # grows when its CI starts needing another host.
  fetchDomains = [
    ".cache.nixos.org"
    "nixos.org"
    "github.com"
    "api.github.com"
    "codeload.github.com"
    "objects.githubusercontent.com"
    "index.crates.io"
    "static.crates.io"
    "crates.io"
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

      # caddy with `admin off` and no certificates writes nothing; point its XDG dirs at
      # the unit's private /tmp anyway so a stray write cannot touch a home.
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

  # Outbound fetches, by domain, because a job has no route of its own: whatever it
  # downloads is resolved and forwarded here, and lands in the access log.
  #
  # Squid's generated config puts extraConfig before its `allow localnet` tail, and
  # localnet covers 172.16.0.0/12 - the job subnet is inside it - so the refusal below
  # has to come from the same file and after the allow, or every domain passes.
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
