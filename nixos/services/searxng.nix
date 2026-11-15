# SearXNG metasearch engine - http://search.framework:7777 (name from the AdGuard rewrite).
# LAN/VPN only: no reverse proxy, no rate limiter.
{ settings, ... }:

let
  # Engine entries merge into SearXNG's defaults by name.
  disabled = map (name: {
    inherit name;
    disabled = true;
  });
  enabled = map (name: {
    inherit name;
    disabled = false;
  });
in
{
  services.searx = {
    enable = true;
    openFirewall = true;

    # Contains SEARXNG_SECRET=... (gitignored); envsubst keeps the key out of the store.
    environmentFile = "${settings.repoPath}/secrets/searxng.env";

    # Valkey backs the search-box autocomplete.
    redisCreateLocally = true;

    settings = {
      server = {
        # Public hostname the Cloudflare "search" tunnel serves.
        base_url = "https://${settings.searchHost}/";
        bind_address = "0.0.0.0";
        port = settings.searxngPort;
        secret_key = "$SEARXNG_SECRET";
      };

      search = {
        # Autocomplete uses duckduckgo.com/ac, which the CAPTCHAs below do not affect.
        autocomplete = "duckduckgo";
        favicon_resolver = "duckduckgo";
        # Without "json" the /search endpoint answers 403 to ?format=json.
        formats = [
          "html"
          "json"
        ];
      };

      engines =
        disabled [
          # These answer with CAPTCHAs or 429.
          "duckduckgo"
          "brave"
          "brave.images"
          "brave.videos"
          "brave.news"
          "startpage"
          "startpage news"
          "startpage images"
          # Needs more than the 3s default timeout.
          "wikidata"
        ]
        ++ enabled [
          "duckduckgo web"
          "bing"
          "privacywall"
          "fynd"
        ]
        ++ [
          # Also hits ReadTimeouts at the 3s default.
          {
            name = "wikipedia";
            timeout = 6.0;
          }
        ];
    };
  };
}
