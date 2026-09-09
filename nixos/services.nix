{ inputs, pkgs, ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = "steelph0enix-pc";

  networking.firewall = {
    enable = true;
    allowPing = true;
    # llama-server (docker) API
    allowedTCPPorts = [ 51536 ];
    allowedUDPPorts = [ 51536 ];
    # Strict reverse path filtering. Use "loose" if asymmetric routing ever shows up (tunnels).
    checkReversePath = "strict";
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
  };

  networking.nameservers = [
    "10.69.69.69"
  ];

  services.blueman.enable = true;
  services.gvfs.enable = true;

  # Owns the CPU governor (`powerManagement.cpuFreqGovernor` would lose to tuned anyway).
  services.tuned = {
    enable = true;
    ppdSupport = true;
    settings = {
      dynamic_tuning = true;
    };

    # Default profile: `desktop`. `recommend` covers `tuned-adm auto`; the DE power-profile
    # slider goes through tuned-ppd, which speaks PPD names - hence `balanced` -> `desktop`.
    recommend.desktop = { };
    ppdSettings = {
      main.default = "balanced";
      profiles = {
        power-saver = "powersave";
        balanced = "desktop";
        performance = "throughput-performance";
      };
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

  # mDNS is here for user-initiated printer discovery only: no inbound mDNS, no publishing of our
  # own records, and cups-browsed stays disabled below (it creates queues from unauthenticated
  # LAN traffic).
  services.avahi = {
    enable = true;
    openFirewall = false;
    publish.enable = false;
  };
  services.system-config-printer.enable = true;
  services.printing = {
    enable = true;
    startWhenNeeded = true;
    drivers = with pkgs; [
      gutenprint
      hplip
      splix
    ];
    browsed.enable = false; # would otherwise default to services.avahi.enable
    cups-pdf.enable = true;
  };

  services.flatpak.enable = true;
  services.fstrim.enable = true;
  services.irqbalance.enable = true;
}
