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
      6969 # Forgejo (HTTP)
      9119 # Hermes Agent dashboard
      22137 # Forgejo (SSH)
      51520 # Hindsight API
      51521 # Hindsight Control Panel
      51536 # LLM Router ROCm (Docker, community Strix Halo image)
      51580 # LLM Router (custom systemd service)
      51581 # LLM Router (native) log web interface
      51569 # LLM Router ROCm log web interface
      51540 # TEI (embedding)
      51541 # TEI (reranking)
      51545 # Web Extract (hermes-local-web-extract)
      6970 # Coverage report viewer (nginx, /srv/coverage)
      6971 # Docs viewer (nginx, /srv/docs)
      # Few generic ports for one-shot/test stuff
      11111
      22222
      33333
      44444
      55555
    ];
    allowedUDPPorts = [ 53 ]; # PiHole DNS
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
  };

  networking.nameservers = [ "192.168.0.185" ];
}
