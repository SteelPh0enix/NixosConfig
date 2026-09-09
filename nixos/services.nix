{ inputs, pkgs, ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = "steelph0enix-pc";

  networking.firewall = {
    enable = true;
    allowPing = true;
    allowedTCPPorts = [ 51536 ];
    allowedUDPPorts = [ 51536 ];
    checkReversePath = false;
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
  };

  networking.nameservers = [
    "10.69.69.69"
  ];

  services.blueman.enable = true;
  services.gvfs.enable = true;

  services.tuned = {
    enable = true;
    ppdSupport = true;
    settings = {
      dynamic_tuning = true;
    };
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

  imports = [ inputs.ucodenix.nixosModules.default ];
  services.ucodenix = {
    enable = true;
    cpuModelId = "00A20F10";
  };

  services.avahi.enable = true;
  services.system-config-printer.enable = true;
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint
      hplip
      splix
    ];
    browsed.enable = true;
    cups-pdf.enable = true;
  };

  services.flatpak.enable = true;
  services.fstrim.enable = true;
  services.irqbalance.enable = true;
}
