# Network-wide DNS + ad blocking (replaces the Pi-hole Docker stack).
#
# `settings` is authoritative: preStart merges the generated AdGuardHome.yaml into
# /var/lib/AdGuardHome/AdGuardHome.yaml on every start, so upstreams, filter lists and custom
# records always come back from Nix, while UI-only tweaks (e.g. a hand-made allowlist entry)
# survive restarts. Admin credentials are created in the UI on first visit and live in the
# state file, not here.
#
# Lists refresh themselves every 24h (dns.filtering.filters_update_interval). A restart forces
# it: the merge above replaces dns.filters, so the `last_updated` stamps are gone and AdGuard
# re-downloads everything - `systemctl restart adguardhome` is the manual "update gravity".
{ lib, ... }:
let
  # This host's LAN address; DNS is published on it plus loopback, like the old Pi-hole.
  lanIp = "192.168.0.185";

  # Custom names, migrated 1:1 from Pi-hole's `dns.hosts`.
  customHosts = {
    "home.ap" = "192.168.0.100";
    "home.gateway" = "192.168.18.1";
    "home.router" = "192.168.0.1";
    "steelph0enix.1337.cx" = lanIp;
    "steelph0enix.framework" = lanIp;
    "steelph0enix.framework-vpn" = "10.69.69.69";
    "steelph0enix.pc" = "192.168.0.150";
    "steelph0enix.worklaptop" = "192.168.0.156";
  };

  # Filter lists, migrated from Pi-hole's gravity DB (all five were enabled).
  filters = [
    {
      name = "StevenBlack hosts";
      url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
    }
    {
      name = "Disconnect ads";
      url = "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt";
    }
    {
      name = "Disconnect tracking";
      url = "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt";
    }
    {
      name = "hagezi pro";
      url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt";
    }
    {
      name = "hagezi pro.plus";
      url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt";
    }
  ];
in
{
  services.adguardhome = {
    enable = true;
    # Only opens the control panel port; port 53 stays in nixos/networking.nix.
    openFirewall = true;
    port = 8123;

    settings = {
      dns = {
        bind_info = [
          { source = lanIp; }
          { source = "127.0.0.1"; }
        ];
        port = 53;

        # AdGuard's own resolver (filter downloads, upstream hostnames). Must never point at
        # this server, or DNS resolution deadlocks on startup.
        bootstrap_dns = [
          "1.1.1.1:53"
          "9.9.9.9:53"
        ];

        # Same resolvers Pi-hole forwarded to.
        upstream_dns = [
          "1.1.1.1"
          "1.0.0.1"
          "2606:4700:4700::1001"
          "2606:4700:4700::1111"
          "8.8.8.8"
          "8.8.4.4"
          "2001:4860:4860::8888"
          "2001:4860:4860::8844"
        ];

        inherit filters;

        custom_dns = lib.mapAttrsToList (question: answer: {
          inherit question;
          answers = [ { inherit answer; type = "A"; } ];
        }) customHosts;
      };
    };
  };
}
