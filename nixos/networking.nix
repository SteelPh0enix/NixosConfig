{ settings, ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = settings.hostId;

  networking.firewall = {
    enable = true;
    allowPing = true;
    # Only ports not managed by services with openFirewall = true.
    allowedTCPPorts = [
      53 # AdGuard Home DNS
      settings.forgejoPort
      settings.coveragePort # Coverage reports (caddy)
      settings.docsPort # Docs (caddy)
      settings.llmPort
      settings.llamaLogsPort
    ];
    allowedUDPPorts = [ 53 ];
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
  };

  networking.nameservers = [ settings.lanIp ];
}
