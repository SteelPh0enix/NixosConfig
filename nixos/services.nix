{ ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = "steelph0enix-pc";

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [ ];

  services.openssh = {
    enable = true;
    settings = {
      X11Forwarding = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
    openFirewall = true;
  };

  services.printing.enable = true;
}
