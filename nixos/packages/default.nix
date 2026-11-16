{ pkgs, ... }:
{
  imports = [
    ./dev.nix
    ./media.nix
    ./system.nix
  ];

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.bat.enable = true;

  programs.cpu-energy-meter.enable = true;
  programs.dconf.enable = true;

  # Thunar does not pull the D-Bus thumbnailer in, and shows generic icons without it.
  services.tumbler.enable = true;

  programs.direnv.enable = true;

  programs.evince.enable = true;

  programs.firefox.enable = true;

  programs.fish.enable = true;

  # sshfs and the AppImage handler both need the setuid fusermount3.
  programs.fuse.enable = true;

  programs.fzf.fuzzyCompletion = true;
  programs.fzf.keybindings = true;

  programs.gnupg.agent.enable = true;

  programs.java = {
    package = pkgs.javaPackages.compiler.temurin-bin.jdk-25;
    enable = true;
    binfmt = true;
  };

  programs.less.enable = true;
  programs.nix-ld.enable = true;
  programs.npm.enable = true;
  programs.screen.enable = true;
  programs.ssh.startAgent = true;
  programs.tcpdump.enable = true;

  # System-wide so volman and D-Bus integration work (home-manager has no thunar option).
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };

  programs.obs-studio = {
    enable = true;
    # No virtual camera: v4l2loopback's depmod maps collide with the kernel's (nixpkgs#576406).
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
    ];
  };

  programs.wireshark = {
    enable = true;
    dumpcap.enable = true;
    usbmon.enable = true;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    protontricks.enable = true;
    localNetworkGameTransfers.openFirewall = true;
    extest.enable = true;
    dedicatedServer.openFirewall = true;
    extraPackages = with pkgs; [
      gamescope
      javaPackages.compiler.temurin-bin.jdk-25
    ];
  };

  # No gamescope session; the package is used per process.
  programs.gamescope.enable = true;

  qt.enable = true;

  xdg.portal.xdgOpenUsePortal = true;
}
