{ ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = "steelph0enix-work-vm";

  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ ];

  services.openssh = {
    enable = true;
    ports = [ 22 ];
    openFirewall = true;
    settings = {
      X11Forwarding = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [ "steelph0enix" ];
    };
  };

  security.pam.services.gdm.enableGnomeKeyring = true;
}
