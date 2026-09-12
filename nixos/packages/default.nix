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

  # D-Bus thumbnailer service (org.freedesktop.thumbnails.Thumbnailer). programs.thunar does not
  # pull it in, so without this Thunar shows generic icons for everything.
  services.tumbler.enable = true;

  # nix-direnv and every shell integration default to true.
  programs.direnv.enable = true;

  programs.evince.enable = true;

  programs.firefox.enable = true;

  # Login shell (users.defaultUserShell); also what puts fish into /etc/shells.
  programs.fish.enable = true;

  # sshfs and the AppImage binfmt handler both need the setuid fusermount3.
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

  # Dolphin leaves with plasma6. System-wide so volman/D-Bus/udisks2 integration works
  # (programs.thunar is a NixOS option; home-manager has no equivalent).
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };

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

  # No Big Picture console session; gamescope stays for per-process use. It was enabled
  # implicitly by programs.steam.gamescopeSession, so it must be named explicitly now.
  programs.gamescope.enable = true;

  qt.enable = true;

  programs.openlogi.enable = true;

  # The Hyprland module enables xdg.portal itself and adds its own portal.
  xdg.portal.xdgOpenUsePortal = true;
}
