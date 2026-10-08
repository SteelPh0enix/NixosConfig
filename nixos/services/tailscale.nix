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
#   3. Admin console -> Machines -> rx-78-fpc: turn on the advertised 192.168.0.0/24 route and the
#      exit node. Advertising is only half of it - until they are switched on, nothing flows.
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

    # Exit node and subnet router. "server" turns on kernel forwarding; "client" is what relaxes
    # NixOS's reverse-path filter, which otherwise drops packets arriving through the tunnel
    # (tailscale#4432). Keep "client" in here even though this box does not use a foreign exit
    # node, and don't lean on another module to set it loose.
    useRoutingFeatures = "both";

    # Gitignored. The generated tailscaled-autoconnect unit re-runs `tailscale up` with this key
    # whenever the node falls back to NeedsLogin, so a rebuild or a logged-out node needs nobody.
    authKeyFile = "${settings.repoPath}/secrets/tailscale-authkey";

    # Deliberately `set`, not `extraUpFlags`: the generated tailscaled-set unit re-applies these
    # on every boot once the node is up, whereas `tailscale up` flags only take effect at the
    # moment of joining - a flag added there does nothing to an already-joined node.
    extraSetFlags = [
      # The NixOS hostname is uppercase; Tailscale wants a lowercase DNS name.
      "--hostname=rx-78-fpc"
      # Tailscale SSH: access is granted by the tailnet, so no host keys to distribute. Needs the
      # Tailscale SSH toggle in the admin console to be turned on.
      "--ssh=true"
      # Lets `tailscale status` run without sudo.
      "--operator=${settings.userName}"
      "--advertise-routes=${lanSubnet}"
      # Offer this box as the tailnet's way out to the internet. Which devices may use it is an
      # ACL/exit-node decision on the admin side, not here.
      "--advertise-exit-node=true"
      # Keep AdGuard Home as this box's resolver (networking.nameservers). Accepting Tailscale DNS
      # would repoint /etc/resolv.conf at tailscaled and deadlock against AdGuard's bootstrap_dns.
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
