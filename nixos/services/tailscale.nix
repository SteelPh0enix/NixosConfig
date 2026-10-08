# Tailscale - reach this box, and through it the LAN, from outside.
#
# Nothing here is exposed to the internet: the tailnet is built by connecting *out* to Tailscale,
# and tailscale0 only exists on this host. tailscaled installs its own `ts-input` accept chain for
# that interface, so the services already running here are reachable over the tailnet without
# adding anything to nixos/networking.nix.
#
# Setup that stays outside Nix:
#   1. Admin console -> Settings -> Keys -> "Generate auth key": reusable, not ephemeral.
#   2. umask 077; printf '%s' 'tskey-auth-...' > ~/nixos-config/secrets/tailscale-authkey
#   3. After the first join: Admin console -> Machines -> rx-78-fpc -> enable the advertised route.
{ config, settings, ... }:
let
  # Offered to the rest of the tailnet. Tailscale SNATs forwarded packets by default
  # (--snat-subnet-routes), so the LAN router needs no return route for tailnet clients.
  lanSubnet = "192.168.0.0/24";
in
{
  services.tailscale = {
    enable = true;

    # UDP 41641, so LAN peers connect directly instead of through DERP relays.
    openFirewall = true;

    # Enables kernel forwarding; advertising lanSubnet does nothing without it. Switch to "both"
    # if this box ever starts *using* another device's exit node.
    useRoutingFeatures = "server";

    # Gitignored. The generated tailscaled-autoconnect unit re-runs `tailscale up` with this key
    # whenever the node falls back to NeedsLogin, so a rebuild or a logged-out node needs nobody.
    authKeyFile = "${settings.repoPath}/secrets/tailscale-authkey";

    extraUpFlags = [
      # The NixOS hostname is uppercase; Tailscale wants a lowercase DNS name.
      "--hostname=rx-78-fpc"
      # Tailscale SSH: access is granted by the tailnet, so no host keys to distribute. Needs the
      # Tailscale SSH toggle in the admin console to be turned on.
      "--ssh"
      # Lets `tailscale status` run without sudo.
      "--operator=${settings.userName}"
      "--advertise-routes=${lanSubnet}"
      # Keep AdGuard Home as the resolver (networking.nameservers). Accepting Tailscale DNS would
      # repoint /etc/resolv.conf at tailscaled and deadlock against AdGuard's own bootstrap_dns.
      "--accept-dns=false"
    ];
  };

  # tailscaled accepts on tailscale0 on its own; repeat it in NixOS terms so the trust does not
  # depend on Tailscale's netfilter mode staying switched on.
  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];

  # Keep NetworkManager off the tunnel: it builds its own nftables zones, and an interface it
  # never got a profile for lands in the blocking one. (Upstream did the same for firewalld.)
  networking.networkmanager.unmanaged = [ config.services.tailscale.interfaceName ];

  # The packaged unit only has an `after` edge on NetworkManager-wait-online, no `wants`, so
  # tailscaled can win the race and read "no network" on boot (nixpkgs#527403).
  systemd.services.tailscaled = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
