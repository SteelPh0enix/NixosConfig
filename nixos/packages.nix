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
      (import ./overlays/llama-cpp.nix { llamaPkgs = pkgsUnstable; })
      (import ./overlays/ollama.nix)
    ];
    system = pkgs.system;
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
    exfat
    exfatprogs
    eza
    fail2ban
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
    linuxHeaders
    linuxKernel.packages.linux_zen.cpupower
    lldb
    lm_sensors
    lsof
    ltrace
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
    pkgsUnstable.nerd-font-patcher
    pkgsUnstable.llama-cpp
    pkgsUnstable.ollama-fpc
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

  services.ollama.package = pkgsUnstable.ollama-fpc;

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
  programs.screen.enable = true;
  programs.ssh.startAgent = true;

  programs.tcpdump.enable = true;
  programs.thefuck.enable = true;
  programs.thefuck.alias = "fk";
  programs.wireshark.enable = true;
  programs.wireshark.dumpcap.enable = true;
  programs.wireshark.usbmon.enable = true;

  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];

  qt.enable = true;
}
