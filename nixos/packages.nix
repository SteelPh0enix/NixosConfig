{
  config,
  pkgs,
  nixpkgs-unstable,
  llama-cpp,
  rust-overlay,
  ...
}:
let
  pkgsUnstable = import nixpkgs-unstable {
    overlays = [
      (llama-cpp.overlays.default)
      (import ./overlays/ccache.nix { cacheDir = config.programs.ccache.cacheDir; })
      (import ./overlays/llama-cpp.nix { overridePkgs = pkgsUnstable; })
    ];
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
    config.rocmSupport = true;
  };
in
{
  nixpkgs.overlays = [
    rust-overlay.overlays.default
    (import ./overlays/ccache.nix { cacheDir = config.programs.ccache.cacheDir; })
  ];

  environment.systemPackages = with pkgs; [
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

    bear
    blueman
    ccache
    cifs-utils
    clang
    curl
    dmidecode
    dnsutils
    docker
    docker-buildx
    dotnet-runtime_9
    dotnet-sdk_9
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
    libunwind
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
    pkgsUnstable.btop-rocm
    pkgsUnstable.clang-tools
    pkgsUnstable.cmake
    pkgsUnstable.eza
    pkgsUnstable.fastfetch
    pkgsUnstable.fd
    pkgsUnstable.ffmpeg-full
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
    pkgsUnstable.uv
    pkgsUnstable.valgrind
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
  programs.obs-studio.enable = true;
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

  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];

  qt.enable = true;
}
