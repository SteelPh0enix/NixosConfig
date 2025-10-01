{ inputs, ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = "steelph0enix-pc";

  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ 16969 ];
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

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.69.69.69/24" ];
    listenPort = 16969;
    privateKeyFile = "/home/steelph0enix/.ssh/wg-privkey";

    peers = [
      {
        publicKey = "k7UoJ41C6XaXbHAgfuDvA6ti0WQLM3miZfJKtgX7PFA=";
        allowedIPs = [ "10.69.69.0/24" ];

        # Set this to the server IP and port.
        endpoint = "10.69.69.1:16969"; # ToDo: route to endpoint not automatically configured https://wiki.archlinux.org/index.php/WireGuard#Loop_routing https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577

        # Send keepalives every 25 seconds. Important to keep NAT tables alive.
        persistentKeepalive = 25;
      }
    ];
  };
}
