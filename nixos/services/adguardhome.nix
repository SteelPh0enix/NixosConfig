# Network-wide DNS and ad blocking. The module merges these settings into the state file on
# every start, so filters, upstreams and rewrites always come back from Nix; UI-only tweaks
# survive. Admin credentials live in the UI, not here.
{ lib, settings, ... }:
let
  customHosts = {
    "home.ap" = "${settings.lanPrefix}100";
    # `home.gateway` is on a different subnet.
    "home.gateway" = "192.168.18.1";
    "home.router" = "${settings.lanPrefix}1";
    "${settings.searchDomain}" = settings.lanIp;
    "steelph0enix.1337.cx" = settings.lanIp;
    "${settings.forgejoDomain}" = settings.lanIp;
    "steelph0enix.pc" = "${settings.lanPrefix}150";
    "steelph0enix.worklaptop" = "${settings.lanPrefix}156";
  };

  filterLists = [
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
  # NetworkManager assigns the LAN address after the services start; binding it too early is
  # fatal for AdGuard.
  systemd.services.adguardhome = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  services.adguardhome = {
    enable = true;
    # Only opens the control panel port; port 53 stays in nixos/networking.nix.
    openFirewall = true;

    settings = {
      http.address = "0.0.0.0:${toString settings.adguardUiPort}";
      dns = {
        bind_hosts = [
          settings.lanIp
          "127.0.0.1"
        ];
        port = 53;

        # AdGuard's default drops bursts; docker builds lose lookups.
        ratelimit = 200;
        ratelimit_subnet_len_ipv4 = 32;

        # AdGuard's own resolver; must not point at this server.
        bootstrap_dns = [
          "1.1.1.1:53"
          "9.9.9.9:53"
        ];

        # IPv4 only: this box has no IPv6 default route.
        upstream_dns = [
          "1.1.1.1"
          "1.0.0.1"
          "8.8.8.8"
          "8.8.4.4"
        ];
      };

      filtering = {
        rewrites = lib.mapAttrsToList (domain: answer: {
          inherit domain answer;
          enabled = true;
        }) customHosts;
      };

      filters = lib.imap0 (
        i: f:
        f
        // {
          id = i + 1;
          enabled = true;
        }
      ) filterLists;
    };
  };
}
