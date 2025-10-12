{
  networking.networkmanager.enable = true;
  networking.hostName = "RX-78-FPC";

  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [
      53
      443
      6969
      8123
      11434
      16969
      22137
      26969
      36969
      46969
      51536
      51537
      51538
      51539
      55569
      56969
    ];
    allowedUDPPorts = [ 53 ];
    extraCommands = ''iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns'';
  };

  networking.nameservers = [ "192.168.0.185" ];
}
