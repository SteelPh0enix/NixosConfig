# SearXNG metasearch engine - http://search.framework:7777 (name from the AdGuard rewrite).
# LAN/VPN only: nothing is port-forwarded on the router, so no reverse proxy and no rate limiter.
{ settings, ... }:

{
  services.searx = {
    enable = true;
    openFirewall = true;

    # Contains SEARXNG_SECRET=... (gitignored). systemd reads it, then the searx-init unit runs
    # the generated settings.yml through envsubst, so the key stays out of the nix store.
    environmentFile = "${settings.repoPath}/secrets/searxng.env";

    # Valkey is the backend for the search-box autocomplete (and for the limiter, unused here).
    redisCreateLocally = true;

    settings = {
      server = {
        base_url = "http://search.framework:7777/";
        bind_address = "0.0.0.0";
        port = 7777;
        secret_key = "$SEARXNG_SECRET";
      };

      # Needs the valkey URL wired up by redisCreateLocally, otherwise suggestions stay empty.
      search.autocomplete = "duckduckgo";
    };
  };
}
