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
      51536 # LLM Router (custom systemd service)
      51537 # LLM Router additional ports
      51538
      51539
      51540
      51541
      18791 # Custom ports (ProtonVPN?)
      18792
      9222 # Custom port
    ];
    allowedUDPPorts = [ 53 ]; # PiHole DNS
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
  };

  networking.nameservers = [ "192.168.0.185" ];
}
