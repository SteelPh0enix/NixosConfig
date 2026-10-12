# Cloudflare Tunnel: https://clanker.steelph0enix.dev/ -> the ROCm llama router on :33333.
# A second tunnel ("search") proxies the SearXNG metasearch engine to https://search.steelph0enix.dev/.
#
# Both tunnels are locally managed (routing declared below, not in the dashboard) and dial out to
# Cloudflare's edge; TLS terminates at the edge with Universal SSL (*.steelph0enix.dev), so the
# machine stays behind the firewall. The LAN keeps reaching SearXNG on search.framework:7777 directly.
#
# cloudflared only ever dials *out* to Cloudflare's edge (QUIC, HTTP/2 fallback), so nothing here
# listens, no NAT rule exists and the machine stays behind the firewall. TLS terminates at the edge
# with Cloudflare's own Universal SSL certificate, which already covers *.steelph0enix.dev - so the
# public side is the standard 443 with no cert to issue or renew, and the hop to the container is
# plain HTTP on loopback. The LAN keeps using :33333 directly (networking.nix).
#
# Authentication is llama-server's own `--api-key` (see LLMs/llm-router-docker-compose.yml): one
# `Authorization: Bearer <key>` guards the tunnel and the LAN port alike, and every OpenAI-compatible
# client already sends it. Cloudflare Access with a service token would be the heavier alternative,
# which has one advantage worth knowing about: it guards only the public hostname, so LAN clients
# could stay keyless.
#
# Routing is declared below rather than in the dashboard, so it survives a rebuild - that needs the
# tunnel to stay *locally managed*. Adding a public hostname route to this tunnel in the Zero Trust
# dashboard makes cloudflared fetch the remote config and silently ignore this ingress.
#
# Setup that stays outside Nix (one time, needs a browser login to the account holding the zone):
#   cf() { nix run nixpkgs#cloudflared -- "$@"; }
#   cf tunnel login                                    # authorizes this origin, writes ~/.cloudflared/cert.pem
#   cf tunnel create clanker \
#     --credentials-file ~/nixos-config/secrets/cloudflare-clanker-credentials.json
#   cf tunnel route dns clanker clanker.steelph0enix.dev   # proxied CNAME -> <uuid>.cfargotunnel.com
#   systemctl status cloudflared-tunnel-clanker && curl -s https://clanker.steelph0enix.dev/health
{
  settings,
  ...
}:
let
  # The router is served by rootless Docker, whose port handler binds IPv4; `localhost` would be a
  # coin toss against ::1.
  router = "http://127.0.0.1:${toString settings.llamaStrixPort}";
in
{
  services.cloudflared = {
    enable = true;

    # Unit name and the credentials file both come from this key; the value cloudflared actually
    # runs is the tunnel UUID inside that file.
    tunnels."clanker" = {
      # Gitignored, same pattern as secrets/tailscale-authkey. Read as a credential at start, so the
      # file never ends up world-readable in the store.
      credentialsFile = "${settings.repoPath}/secrets/cloudflare-clanker-credentials.json";

      # The whole hostname goes to the router: the API key already guards every endpoint except
      # /health and the UI assets. If a narrower public surface is ever wanted, add a `path` regex to
      # the entry below and the leftover requests fall through to `default`.
      ingress = {
        "clanker.steelph0enix.dev" = router;
      };

      # Any hostname the tunnel is pointed at that is not routed above, and any path the rule above
      # rejects, ends here instead of reaching the router.
      default = "http_status:404";

      originRequest = {
        # A cold router answers 503 while it loads a preset, which is a healthy answer; these only
        # cover the TCP/keepalive side of the loopback hop.
        connectTimeout = "10s";
        tcpKeepAlive = "30s";
      };
    };

    # Dedicated tunnel for the SearXNG metasearch engine (nixos/services/searxng.nix).
    # One-time setup stays outside Nix (same as the clanker tunnel above):
    #   cloudflared tunnel create search --credentials-file ~/nixos-config/secrets/cloudflare-search-credentials.json
    #   cloudflared tunnel route dns search search.steelph0enix.dev
    tunnels."search" = {
      credentialsFile = "${settings.repoPath}/secrets/cloudflare-search-credentials.json";

      # Only the search host is routed here; anything else on the tunnel falls through to default.
      ingress = {
        "search.steelph0enix.dev" = "http://127.0.0.1:7777";
      };

      default = "http_status:404";

      originRequest = {
        connectTimeout = "10s";
        tcpKeepAlive = "30s";
      };
    };
  };
}
