{
  config,
  pkgs,
  pkgsUnstable,
  rust-overlay,
  ...
}:
let
  pkgsUnstable' = pkgsUnstable.extend (import ../overlays/llama-cpp.nix);
in
{
  imports = [
    ./dev.nix
    ./system.nix
    ./media.nix
    ./apps.nix
  ];

  nixpkgs.overlays = [
    rust-overlay.overlays.default
    (import ../overlays/ccache.nix { cacheDir = config.programs.ccache.cacheDir; })
  ];

  systemd.packages = with pkgs; [ lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.bat = {
    enable = true;
    package = pkgsUnstable.bat;
  };

  programs.ccache.enable = true;
  programs.ccache.cacheDir = "/var/cache/ccache";
  programs.cpu-energy-meter.enable = true;
  programs.dconf.enable = true;

  programs.direnv = {
    enable = true;
    enableFishIntegration = true;
    package = pkgsUnstable.direnv;
    nix-direnv = {
      enable = true;
      package = pkgsUnstable.nix-direnv;
    };
  };

  programs.evince.enable = true;

  programs.firefox = {
    enable = true;
    package = pkgsUnstable.firefox;
  };

  programs.fish = {
    package = pkgs.fish;
    enable = true;
  };

  programs.fzf = {
    fuzzyCompletion = true;
    keybindings = true;
  };

  programs.gnupg.agent = {
    enable = true;
    enableBrowserSocket = true;
  };

  programs.java = {
    package = pkgsUnstable.javaPackages.compiler.temurin-bin.jdk-25;
    enable = true;
    binfmt = true;
  };

  programs.less.enable = true;
  programs.nix-ld.enable = true;
  programs.npm.enable = true;
  programs.screen.enable = true;
  programs.ssh.startAgent = true;
  programs.tcpdump.enable = true;

  programs.obs-studio = {
    enable = true;
    package = pkgsUnstable.obs-studio;
    enableVirtualCamera = true;
    plugins = [
      pkgsUnstable.obs-studio-plugins.waveform
      pkgsUnstable.obs-studio-plugins.obs-vnc
      pkgsUnstable.obs-studio-plugins.obs-vkcapture
      pkgsUnstable.obs-studio-plugins.obs-vaapi
      pkgsUnstable.obs-studio-plugins.obs-text-pthread
      pkgsUnstable.obs-studio-plugins.obs-pipewire-audio-capture
      pkgsUnstable.obs-studio-plugins.obs-mute-filter
      pkgsUnstable.obs-studio-plugins.obs-markdown
      pkgsUnstable.obs-studio-plugins.obs-gstreamer
      pkgsUnstable.obs-studio-plugins.obs-dvd-screensaver
    ];
  };

  programs.wireshark = {
    package = pkgsUnstable.wireshark;
    enable = true;
    dumpcap.enable = true;
    usbmon.enable = true;
  };

  programs.steam = {
    package = pkgsUnstable.steam;
    enable = true;
    remotePlay.openFirewall = true;
    protontricks.enable = true;
    localNetworkGameTransfers.openFirewall = true;
    extest.enable = true;
    dedicatedServer.openFirewall = true;
    gamescopeSession.enable = true;
    extraPackages = with pkgs; [
      gamescope
      pkgsUnstable.javaPackages.compiler.temurin-bin.jdk-25
    ];
  };

  programs.sleepy-launcher.enable = true;

  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];

  qt.enable = true;
}
