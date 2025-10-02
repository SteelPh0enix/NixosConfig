{
  lib,
  pkgs,
  ...
}:
{
  networking.networkmanager.enable = true;
  networking.hostName = "RX-78-FPC";

  services.fail2ban.enable = true;
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
      55569
    ];
    allowedUDPPorts = [ 53 ];
  };

  services.openssh = {
    enable = true;
    ports = [ 22137 ];
    openFirewall = true;
    settings = {
      X11Forwarding = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [ "steelph0enix" ];
      LogLevel = "VERBOSE";
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

  services.ollama = {
    enable = true;
    rocmOverrideGfx = "11.5.1";
    host = "0.0.0.0";
    port = 11434;
    user = "ollama";
    acceleration = "rocm";
    environmentVariables = {
      HIP_VISIBLE_DEVICES = "0";
      ROCR_VISIBLE_DEVICES = "0";
      OLLAMA_FLASH_ATTENTION = "1";
      
    };
  };
}
