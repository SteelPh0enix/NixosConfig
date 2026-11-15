# The tailnet is outbound-only; tailscaled handles its own firewall.
{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  # UDP GRO fix for a node that forwards for the tailnet; tailscale warns about it on every `up`.
  udpGroFix = pkgs.writeShellScript "tailscale-udp-gro" ''
    PATH=${
      lib.makeBinPath [
        pkgs.gnused
        pkgs.iproute2
      ]
    }
    uplink=$(ip -o route get 8.8.8.8 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')
    if [ -n "$uplink" ]; then
      ${lib.getExe pkgs.ethtool} -K "$uplink" rx-udp-gro-forwarding on rx-gro-list off \
        || echo "could not set UDP GRO forwarding on $uplink"
    fi
  '';
in
{
  services.tailscale = {
    enable = true;

    # LAN peers connect directly instead of through DERP relays.
    openFirewall = true;
    port = settings.tailscalePort;

    # `client` relaxes the reverse-path filter that would drop tunnel traffic (tailscale#4432).
    useRoutingFeatures = "both";

    # Gitignored; the generated autoconnect unit re-runs `tailscale up` after NeedsLogin.
    authKeyFile = "${settings.repoPath}/secrets/tailscale-authkey";

    # `set`, not `extraUpFlags`: the set unit re-applies these on every boot, while `up` flags
    # only take effect when joining.
    extraSetFlags = [
      # The NixOS hostname is uppercase; Tailscale wants a lowercase DNS name.
      "--hostname=${lib.toLower settings.hostId}"
      # Access is granted by the tailnet's ACLs.
      "--ssh=true"
      # Lets `tailscale status` run without sudo.
      "--operator=${settings.userName}"
      "--advertise-routes=${settings.lanSubnet}"
      # Exit-node use is approved on the admin side.
      "--advertise-exit-node=true"
      # Keep AdGuard as the resolver; accepting Tailscale DNS would deadlock against its
      # bootstrap_dns.
      "--accept-dns=false"
    ];
  };

  # tailscaled accepts on tailscale0 on its own; repeat it so the trust does not depend on
  # Tailscale's netfilter mode.
  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];

  # NetworkManager builds its own nftables zones, and an interface it has no profile for lands in
  # the blocking one.
  networking.networkmanager.unmanaged = [ config.services.tailscale.interfaceName ];

  # The packaged unit lacks a `wants`, so tailscaled can read "no network" on boot (nixpkgs#527403).
  systemd.services.tailscaled = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  # The features do not survive a reboot or driver reset: set them at boot and on each
  # NetworkManager activation of the interface.
  systemd.services.tailscale-udp-gro = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = udpGroFix;
    };
  };

  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = udpGroFix;
    }
  ];
}
