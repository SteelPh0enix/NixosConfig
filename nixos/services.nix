{
  lib,
  pkgs,
  # inputs,
  ...
}:
{
  networking.networkmanager.enable = true;
  networking.hostName = "RX-78-FPC";

  services.printing.enable = true;
  services.blueman.enable = true;
  services.jackett.enable = true;
  services.flaresolverr.enable = true;
  services.thermald.enable = true;

  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [
      53
      443
      8123
      11434
      51536
      51537
      51538
      51539
      55569
    ];
    allowedUDPPorts = [ 53 ];
    extraCommands = ''iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns'';
  };

  networking.nameservers = [ "127.0.0.1" ];

  services.openssh = {
    enable = true;
    ports = [ 22137 ];
    openFirewall = true;
    settings = {
      X11Forwarding = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [
        "steelph0enix"
        "quake"
      ];
      LogLevel = "VERBOSE";
      MaxAuthTries = 10;
    };
  };

  # imports = [ inputs.ucodenix.nixosModules.default ];
  # services.ucodenix = {
  #   enable = true;
  #   cpuModelId = "00B70F00";
  # };

  services.gvfs = {
    enable = true;
    package = lib.mkForce pkgs.gnome.gvfs;
  };

  services.tuned = {
    enable = true;
    settings = {
      daemon = true;
      dynamic_tuning = true;
      recommend_command = true;
    };
  };
}
