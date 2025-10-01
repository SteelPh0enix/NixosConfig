{ pkgs, ... }:
let
  internetIface = "enp191s0";
  wireguardPort = 16969;
  wireguardIp = "10.69.69.69/24";
in
{
  networking.nat = {
    enable = true;
    enableIPv6 = true;
    externalInterface = internetIface;
    internalInterfaces = [ "wg0" ];
  };

  networking.firewall.allowedUDPPorts = [
    wireguardPort
  ];

  networking.wg-quick.interfaces = {
    wg0 = {
      address = [
        wireguardIp
      ];
      listenPort = wireguardPort;
      privateKeyFile = "/root/wireguard/wg-private";

      postUp = ''
        ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${wireguardIp} -o ${internetIface} -j MASQUERADE
      '';

      postDown = ''
        ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${wireguardIp} -o ${internetIface} -j MASQUERADE
      '';

      peers = [
        {
          publicKey = "QirNxLiqQQdWlsg3B354P7RsM1NmJtCgo8NbqBxeciM=";
          presharedKeyFile = "/root/wireguard/wg-preshared-mainpc";
          allowedIPs = [
            "10.69.69.1/32"
          ];
        }
      ];
    };
  };
}
