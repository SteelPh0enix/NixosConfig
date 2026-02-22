{
  config,
  pkgs,
  nixpkgs-unstable,
  llama-cpp,
  rust-overlay,
  inputs,
  ...
}:
let
  pkgsUnstable = import nixpkgs-unstable {
    overlays = [
      (import ./overlays/rocm.nix { overridePkgs = pkgsUnstable; })
      (llama-cpp.overlays.default)
      (import ./overlays/llama-cpp.nix { overridePkgs = pkgsUnstable; })
    ];
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
    config.rocmSupport = false;
  };
in
{
  nixpkgs.overlays = [
    rust-overlay.overlays.default
    (import ./overlays/freecad.nix)
  ];

  environment.systemPackages = with pkgs; [

    bear
    bindfs
    blueman
    ccache
    clang
    curl
    dmidecode
    dnsutils
    docker
    docker-buildx
    exfat
    exfatprogs
    figlet
    file
    findutils
    flac
    gawk
    gcc
    gdb
    gh
    gnugrep
    gnused
    gnutar
    gparted
    gst_all_1.gst-libav
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-vaapi
    gst_all_1.gstreamer
    hdparm
    icu
    inetutils
    lact
    libnatpmp
    libva-utils
    linuxHeaders
    linuxKernel.packages.linux_zen.cpupower
    lldb
    lm_sensors
    lsof
    ltrace
    nil
    nixd
    nixfmt
    nixpkgs-review
    nmap
    ntfs3g
    openssh
    openssl
    p7zip
    parted
    pciutils
    pkg-config
    pkgsUnstable.btop-rocm
    pkgsUnstable.clang-tools
    pkgsUnstable.cmake
    pkgsUnstable.eza
    pkgsUnstable.fastfetch
    pkgsUnstable.fd
    pkgsUnstable.ffmpeg-full
    pkgsUnstable.flaresolverr
    pkgsUnstable.fzf
    pkgsUnstable.glibc
    pkgsUnstable.jq
    pkgsUnstable.llama-cpp
    pkgsUnstable.mc
    pkgsUnstable.ncdu
    pkgsUnstable.nerd-font-patcher
    pkgsUnstable.ninja
    pkgsUnstable.radeontop
    pkgsUnstable.ripgrep
    pkgsUnstable.rust-motd
    pkgsUnstable.steam-tui
    pkgsUnstable.steamcmd
    pkgsUnstable.uv
    pkgsUnstable.valgrind
    pkgsUnstable.weechat
    psmisc
    rsync
    socat
    sqlite
    strace
    sysstat
    tcpdump
    thermald
    traceroute
    tree
    unzip
    usbutils
    vk-bootstrap
    vkd3d
    vkdisplayinfo
    vkmark
    wget
    which
    wireguard-tools
    xz
    zip
    zstd

    inputs.compose2nix.packages.x86_64-linux.default

    (rust-bin.stable.latest.default.override {
      extensions = [
        "cargo"
        "rust-analysis"
        "rust-src"
        "rust-std"
        "rustc"
        "rustfmt"
      ];
    })
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

  programs.git = {
    enable = true;
    package = pkgsUnstable.gitFull;
    lfs = {
      enable = true;
      enablePureSSHTransfer = true;
      package = pkgsUnstable.git-lfs;
    };
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

  programs.wireshark = {
    package = pkgsUnstable.wireshark;
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
    gamescopeSession.enable = true;
    extraPackages = with pkgs; [
      gamescope
      pkgsUnstable.javaPackages.compiler.temurin-bin.jdk-25
    ];
  };

  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];

  qt.enable = true;
}
