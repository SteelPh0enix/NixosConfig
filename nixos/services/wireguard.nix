{ pkgs, ... }:
{
  networking.nat.enable = true;
  networking.nat.externalInterface = "enp191s0";
  networking.nat.internalInterfaces = [ "wg0" ];
  networking.firewall = {
    allowedUDPPorts = [ 16969 ];
  };

  networking.wireguard.enable = true;
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.69.69.1/24" ];
    listenPort = 16969;
    # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
    # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
    postSetup = ''
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.69.69.0/24 -o enp191s0 -j MASQUERADE
    '';

    # This undoes the above command
    postShutdown = ''
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.69.69.0/24 -o enp191s0 -j MASQUERADE
    '';

    privateKeyFile = "/home/steelph0enix/.ssh/wg-private";

    peers = [
      {
        publicKey = "QirNxLiqQQdWlsg3B354P7RsM1NmJtCgo8NbqBxeciM=";
        allowedIPs = [ "10.69.69.69/32" ];
      }
    ];
  };
}
