{ inputs, ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = "steelph0enix-pc";

  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ 16969 ];
    checkReversePath = false;
  };

  services.fail2ban.enable = true;
  services.printing.enable = true;
  services.blueman.enable = true;
  services.jackett.enable = true;
  services.flaresolverr.enable = true;
  services.thermald.enable = true;
  services.gvfs.enable = true;

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

  imports = [ inputs.ucodenix.nixosModules.default ];
  services.ucodenix = {
    enable = true;
    cpuModelId = "00A20F10";
  };

  networking.wg-quick.interfaces = {
    wg0 = {
      address = [ "10.69.69.1/24" ];
      privateKeyFile = "/home/steelph0enix/.ssh/wg-private";

      peers = [
        {
          publicKey = "k7UoJ41C6XaXbHAgfuDvA6ti0WQLM3miZfJKtgX7PFA=";
          presharedKeyFile = "/home/steelph0enix/.ssh/wg-preshared";
          allowedIPs = [ "0.0.0.0/0" ];

          endpoint = "192.168.0.185:16969";

          # Send keepalives every 25 seconds. Important to keep NAT tables alive.
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
