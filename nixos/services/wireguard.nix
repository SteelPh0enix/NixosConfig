{ pkgs, ... }:
let
  protonIface = "wg-proton";
  wireguardIface = "wg-steelph0enix";
  wireguardPort = 16969;
  protonPort = 16970;
  wireguardIp = "10.69.69.69";
  wireguardIpMasked = "${wireguardIp}/24";
  protonIp = "10.2.0.2";
  protonIpMasked = "${protonIp}/32";
in
{
  networking.nat = {
    enable = true;
    enableIPv6 = true;
    externalInterface = protonIface;
    internalInterfaces = [ wireguardIface ];
  };

  networking.firewall.allowedUDPPorts = [
    wireguardPort
  ];

  networking.defaultGateway = {
    address = protonIp;
    interface = protonIface;
  };

  networking.wg-quick.interfaces = {
    ${wireguardIface} = {
      autostart = true;
      dns = [ wireguardIp ];
      address = [ wireguardIpMasked ];
      listenPort = wireguardPort;
      privateKeyFile = "/root/wireguard/wg-private";

      postUp = ''
        ${pkgs.iptables}/bin/iptables -A FORWARD -i ${wireguardIface} -j ACCEPT
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${wireguardIpMasked} -o ${protonIface} -j MASQUERADE
      '';

      postDown = ''
        ${pkgs.iptables}/bin/iptables -D FORWARD -i ${wireguardIface} -j ACCEPT
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${wireguardIpMasked} -o ${protonIface} -j MASQUERADE
      '';

      peers = [
        {
          publicKey = "QirNxLiqQQdWlsg3B354P7RsM1NmJtCgo8NbqBxeciM=";
          presharedKeyFile = "/root/wireguard/wg-preshared-mainpc";
          allowedIPs = [
            "10.69.69.1/32"
          ];
        }
        {
          publicKey = "O1U98c6rt2U7ZmO7PPXj26dtW1TXaMRnCD+U/p6bBhs=";
          presharedKeyFile = "/root/wireguard/wg-preshared-flip";
          allowedIPs = [
            "10.69.69.5/32"
          ];
        }
        {
          publicKey = "xhSLM03wpnzAbKm5EZ2DRSgU4HaEMj99RsibalZelBY=";
          presharedKeyFile = "/root/wireguard/wg-preshared-quake";
          allowedIPs = [
            "10.69.69.10/32"
          ];
        }
      ];
    };

    ${protonIface} = {
      autostart = true;
      dns = [ wireguardIp ];
      privateKeyFile = "/root/wireguard/wg-proton-private";
      address = [ protonIpMasked ];
      listenPort = protonPort;

      peers = [
        {
          publicKey = "HHSEAw01hRxWiesolxYPU8n86ZmbsKSM+zmCk2OPc24=";
          allowedIPs = [
            "0.0.0.0/0"
            "::/0"
          ];
          endpoint = "79.127.186.165:51820";
        }
      ];
    };
  };
}
