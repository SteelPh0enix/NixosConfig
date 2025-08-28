{ ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = "steelph0enix-pc";

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [ ];
}
