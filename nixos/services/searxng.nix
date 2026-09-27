# SearXNG metasearch engine - http://search.framework:7777 (name from the AdGuard rewrite).
# LAN/VPN only: nothing is port-forwarded on the router, so no reverse proxy and no rate limiter.
{ settings, ... }:

let
  # Engine entries are merged into SearXNG's default engines by name. The names below were
  # checked against this instance (/stats, /stats/errors): the scraped engines get their IP
  # blocked (CAPTCHA / HTTP 429) and that is not fixable from settings - only via official
  # APIs (see braveapi/kagi below) or another exit IP.
  disabled = map (name: { inherit name; disabled = true; });
  enabled = map (name: { inherit name; disabled = false; });
in
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

      search = {
        # Needs the valkey URL wired up by redisCreateLocally, otherwise suggestions stay empty.
        # Autocomplete uses duckduckgo.com/ac, which is not affected by the CAPTCHA below.
        autocomplete = "duckduckgo";
        favicon_resolver = "duckduckgo";
      };

      engines =
        disabled [
          # html.duckduckgo.com answers with a challenge form; "duckduckgo web" (enabled below)
          # uses the duckduckgo.com API instead and works.
          "duckduckgo"
          # search.brave.com answers 429 to every request, all four categories share it.
          "brave"
          "brave.images"
          "brave.videos"
          "brave.news"
          # startpage.com redirects to /sp/captcha before a search can even start.
          "startpage"
          "startpage news"
          "startpage images"
          # SPARQL on query.wikidata.org needs way more than the 3s default timeout.
          "wikidata"
        ]
        ++ enabled [
          "duckduckgo web"
          "bing"
          "privacywall"
          "fynd"
        ]
        ++ [
          # Wikipedia also hit ReadTimeouts with the default 3s.
          {
            name = "wikipedia";
            timeout = 6.0;
          }
          # Official APIs are the only CAPTCHA-free Brave/Google results; both need a key in
          # secrets/searxng.env (envsubst already runs over the generated settings.yml):
          # { name = "braveapi"; inactive = false; api_key = "$SEARXNG_BRAVE_API_KEY"; }
          # { name = "kagi"; inactive = false; api_key = "$KAGI_API_KEY"; }
        ];
    };
  };
}
