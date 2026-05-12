{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./dev.nix
    ./system.nix
    ./media.nix
    ./apps.nix
  ];

  nixpkgs.overlays = [
    inputs.rust-overlay.overlays.default
    inputs.nix-cachyos-kernel.overlays.pinned
  ];

  systemd.packages = with pkgs; [ lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.bat.enable = true;

  programs.cpu-energy-meter.enable = true;
  programs.dconf.enable = true;

  programs.direnv = {
    enable = true;
    enableFishIntegration = true;
    nix-direnv.enable = true;
  };

  programs.evince.enable = true;

  programs.firefox.enable = true;

  programs.fish.enable = true;

  programs.fzf.fuzzyCompletion = true;
  programs.fzf.keybindings = true;

  programs.gnupg.agent = {
    enable = true;
    enableBrowserSocket = true;
  };

  programs.java = {
    package = pkgs.javaPackages.compiler.temurin-bin.jdk-25;
    enable = true;
    binfmt = true;
  };

  programs.less.enable = true;
  programs.nix-ld.enable = true;
  programs.npm = {
    enable = true;
    npmrc = ''
      min-release-age=7
      minimum-release-age=10080
    '';
  };
  programs.screen.enable = true;
  programs.ssh.startAgent = true;
  programs.tcpdump.enable = true;

  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
    plugins = [
      pkgs.obs-studio-plugins.waveform
      pkgs.obs-studio-plugins.obs-vnc
      pkgs.obs-studio-plugins.obs-vkcapture
      pkgs.obs-studio-plugins.obs-vaapi
      pkgs.obs-studio-plugins.obs-text-pthread
      pkgs.obs-studio-plugins.obs-pipewire-audio-capture
      pkgs.obs-studio-plugins.obs-mute-filter
      pkgs.obs-studio-plugins.obs-markdown
      pkgs.obs-studio-plugins.obs-gstreamer
      pkgs.obs-studio-plugins.obs-dvd-screensaver
    ];
  };

  # programs.wireshark = {
  #   enable = true;
  #   dumpcap.enable = true;
  #   usbmon.enable = true;
  # };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    protontricks.enable = true;
    localNetworkGameTransfers.openFirewall = true;
    extest.enable = true;
    dedicatedServer.openFirewall = true;
    gamescopeSession.enable = true;
    extraPackages = with pkgs; [
      gamescope
      javaPackages.compiler.temurin-bin.jdk-25
    ];
  };

  programs.sleepy-launcher.enable = true;

  qt.enable = true;
}
