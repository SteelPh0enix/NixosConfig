{
  networking.networkmanager.enable = true;
  networking.hostName = "steelph0enix-pc";

  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ ];

  services.openssh = {
    enable = true;
    ports = [ 33445 ];
    openFirewall = true;
    settings = {
      X11Forwarding = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [ "steelph0enix" ];
      LogLevel = "VERBOSE";
    };
  };

  services.fail2ban.enable = true;
  services.printing.enable = true;
}
