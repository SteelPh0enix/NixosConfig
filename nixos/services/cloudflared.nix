# Cloudflare tunnels: clanker -> llmPort, search -> SearXNG. Routing is locally managed; a
# dashboard route silently overrides it.
{
  settings,
  ...
}:
let
  # The engines bind IPv4 explicitly (`--host`); `localhost` would be a coin toss against ::1.
  router = "http://${settings.llmHost}:${toString settings.llmPort}";

  # cloudflared resolves the edge once at startup and exits if DNS is not ready yet.
  dnsGate = {
    wants = [ "dns-ready.target" ];
    after = [ "dns-ready.target" ];

    serviceConfig.RestartSec = "5s";

    unitConfig = {
      # 0 means no rate limit; combined with RestartSec above, a bad minute at boot self-heals.
      StartLimitIntervalSec = 0;
    };
  };

  mkTunnel =
    {
      credentialsFile,
      hostname,
      upstream,
    }:
    {
      inherit credentialsFile;
      ingress.${hostname} = upstream;
      default = "http_status:404";
      originRequest = {
        connectTimeout = "10s";
        tcpKeepAlive = "30s";
      };
    };
in
{
  services.cloudflared = {
    enable = true;

    tunnels."clanker" = mkTunnel {
      credentialsFile = "${settings.repoPath}/secrets/cloudflare-clanker-credentials.json";
      hostname = settings.clankerHost;
      upstream = router;
    };

    tunnels."search" = mkTunnel {
      credentialsFile = "${settings.repoPath}/secrets/cloudflare-search-credentials.json";
      hostname = settings.searchHost;
      upstream = "http://127.0.0.1:${toString settings.searxngPort}";
    };
  };

  systemd.services.cloudflared-tunnel-clanker = dnsGate;
  systemd.services.cloudflared-tunnel-search = dnsGate;
}
