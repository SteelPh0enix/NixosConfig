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

  # pi routes its models by these two names, and its extensions decide whether a server is llama.cpp in well under two
  # seconds - too little for a round trip to the LAN resolver when that one is slow to answer. Keep in step with the
  # addresses the DHCP reservations hold; search.framework is the same machine as the framework's llama.cpp router.
  networking.hosts = {
    "192.168.0.185" = [
      "steelph0enix.framework"
      "search.framework"
    ];
    "192.168.0.150" = [ "steelph0enix.pc" ];
  };

  # AdGuard answers in ~15ms but loses about one UDP reply in twenty, and glibc's default of one 5s wait per attempt
  # turns a single loss into a 5s stall and a pair into a 10s failure. Ask sooner and more often, and ask for the
  # address families one after the other rather than together, which is what lets a reply go missing in the first place.
  networking.resolvconf.extraOptions = [
    "timeout:2"
    "attempts:3"
    "single-request-reopen"
  ];

  networking.firewall = {
    enable = true;
    # llama.cpp router and its log viewer (nixos/services/llama-server-vulkan), used by the other
    # box, and Strata (nixos/services/strata). None of them carries an API key: the LAN is the ACL.
    allowedTCPPorts = [
      settings.llmPort
      settings.llamaLogsPort
      settings.strataPort
    ];
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

  # Counterpart of the remote host's sshd AcceptEnv: without COLORTERM (WezTerm's truecolor hint)
  # TUIs over SSH fall back to the 256-colour palette. Kept system-wide, so ~/.ssh/config stays
  # hand-owned.
  programs.ssh.extraConfig = ''
    Host *
      SendEnv COLORTERM
  '';

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
  };
  services.system-config-printer.enable = true;
  services.printing = {
    enable = true;
    startWhenNeeded = true;
    drivers = with pkgs; [
      gutenprint
      # hplip 3.26.4 hands the gapps wrapper args to the C wrapper generator, and
      # the dconf GIO path among them is not an argument it knows: the build dies
      # with "makeCWrapper: Unknown argument .../dconf-.../lib/gio/modules".
      # Upstream fixed it in 3.26.6 (nixpkgs commit 950cb897); drop this override
      # once the nixos-unstable branch carries that.
      (hplip.override {
        wrapGAppsHook3 = wrapGAppsHook3.override { withDconf = false; };
      })
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
  services.fwupd.enable = true;
}
