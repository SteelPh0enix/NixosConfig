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
      (import ./overlays/llama-cpp.nix { llamaPkgs = pkgsUnstable; })
    ];
    system = pkgs.system;
    config.allowUnfree = true;
    config.rocmSupport = true;
  };
in
{
  nixpkgs.overlays = [
    rust-overlay.overlays.default
    (import ./overlays/ccache.nix { cacheDir = config.programs.ccache.cacheDir; })
    (import ./overlays/freecad.nix)
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

    pkgsUnstable.nerd-font-patcher
    # pkgsUnstable.llama-cpp

    bear
    blueman
    btop-rocm
    ccache
    clang
    clang-tools
    cmake
    curl
    dmidecode
    dnsutils
    docker
    docker-buildx
    dotnet-runtime_9
    dotnet-sdk_9
    exfat
    exfatprogs
    eza
    fastfetch
    fd
    ffmpeg-full
    file
    findutils
    flac
    flaresolverr
    fzf
    gawk
    gcc
    gdb
    gh
    git
    git-lfs
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
    jackett
    jq
    lact
    libunwind
    linuxHeaders
    linuxKernel.packages.linux_zen.cpupower
    lldb
    lm_sensors
    lsof
    ltrace
    ncdu
    nil
    ninja
    nixd
    nixfmt-rfc-style
    nixpkgs-review
    nmap
    ntfs3g
    openssh
    openssl
    p7zip
    parted
    pciutils
    psmisc
    ripgrep
    rsync
    rust-analyzer
    socat
    sqlite
    strace
    sysstat
    tcpdump
    thermald
    tree
    usbutils
    uv
    valgrind
    wget
    which
    wireguard-tools
    wireshark
    xz
    zip
    zstd
  ];

  systemd.packages = with pkgs; [ lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  programs.bat.enable = true;
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
  programs.firefox.enable = true;
  programs.fish.enable = true;
  programs.fzf.fuzzyCompletion = true;
  programs.fzf.keybindings = true;
  programs.gamemode.enable = true;
  programs.git.enable = true;
  programs.git.lfs.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableBrowserSocket = true;
  };
  programs.java.enable = true;
  programs.java.binfmt = true;
  programs.lazygit.enable = true;
  programs.less.enable = true;
  programs.nix-ld.enable = true;
  programs.npm.enable = true;
  programs.obs-studio.enable = true;
  programs.screen.enable = true;
  programs.ssh.startAgent = true;
  programs.steam = {
    enable = true;
    localNetworkGameTransfers.openFirewall = true;
    protontricks.enable = true;
    remotePlay.openFirewall = true;
  };
  programs.tcpdump.enable = true;
  programs.thefuck.enable = true;
  programs.thefuck.alias = "fk";
  programs.thunderbird.enable = true;
  programs.wireshark.enable = true;
  programs.wireshark.dumpcap.enable = true;
  programs.wireshark.usbmon.enable = true;

  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];

  qt.enable = true;
}
