{
  networking.networkmanager.enable = true;
  networking.hostName = "RX-78-FPC";

  networking.firewall = {
    enable = true;
    allowPing = true;
    # Only ports not managed by services with openFirewall = true
    allowedTCPPorts = [
      53 # PiHole DNS (Docker service)
      443 # HTTPS
      6969 # Gitea (HTTP)
      22137 # Gitea (SSH)
      51536 # LLM Router (custom systemd service)
      51569 # LLM Router log web interface
    ];
    allowedUDPPorts = [ 53 ]; # PiHole DNS
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
  };

  networking.nameservers = [ "192.168.0.185" ];
}
