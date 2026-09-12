{
  inputs,
  lib,
  pkgs,
  settings,
  ...
}:
let
  # Noctalia's power slider talks to the power-profiles-daemon API, which tuned-ppd maps onto
  # these three tuned profiles; nothing else can be selected.
  selectableProfiles = {
    power-saver = "powersave";
    balanced = "desktop";
    performance = "throughput-performance";
  };

  # tuned's audio plugin re-enables HDA autosuspend (`timeout=10`) on every profile activation,
  # which makes the speakers buzz a few seconds after audio stops. Shadowing the profiles in
  # /etc/tuned/profiles wins over the ones shipped with tuned (later `profile_dirs` entry is
  # searched first) and keeps audio power management off for good.
  noAudioPmProfile =
    name:
    pkgs.runCommand "tuned-${name}-no-audio-pm.conf" { } ''
      cat ${pkgs.tuned}/lib/tuned/profiles/${name}/tuned.conf > $out
      printf '\n[audio]\ntimeout=0\nreset_controller=false\n' >> $out
    '';
in
{
  networking.networkmanager.enable = true;
  networking.hostName = settings.hostId;

  networking.firewall = {
    enable = true;
    # llama-server (docker) API
    allowedTCPPorts = [ 51536 ];
    # Strict reverse path filtering. Use "loose" if asymmetric routing ever shows up (tunnels).
    checkReversePath = "strict";
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
  };

  # No blueman-applet: Noctalia talks to BlueZ directly (bluetooth widget, `bluetooth-*` IPC).
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
    # `battery_detection = false` and an empty `battery` map: nothing outside those three is reachable.
    ppdSettings = {
      main = {
        default = "balanced";
        battery_detection = false;
      };
      profiles = selectableProfiles;
      battery = { };
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
      AllowUsers = [ settings.userName ];
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

  environment.etc =
    lib.mapAttrs' (
      _: name: lib.nameValuePair "tuned/profiles/${name}/tuned.conf" { source = noAudioPmProfile name; }
    ) selectableProfiles
    // {
      # `powersave` runs ${i:PROFILE_DIR}/script.sh, which now resolves to the shadowing profile dir.
      "tuned/profiles/powersave/script.sh" = {
        source = "${pkgs.tuned}/lib/tuned/profiles/powersave/script.sh";
        mode = "0755";
      };
    };

  services.flatpak.enable = true;
  services.fstrim.enable = true;
  services.irqbalance.enable = true;
}
