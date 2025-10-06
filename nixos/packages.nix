{
  config,
  pkgs,
  pkgsUnstable,
  rust-overlay,
  ...
}:
{
  nixpkgs.overlays = [
    (import ./overlays/ccache.nix { cacheDir = config.programs.ccache.cacheDir; })
    rust-overlay.overlays.default
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

    automake
    bear
    black
    btop
    ccache
    cmake
    colordiff
    curl
    dmidecode
    dnsutils
    docker
    docker-buildx
    dotnet-runtime_9
    dotnet-sdk_9
    eslint
    exfat
    exfatprogs
    eza
    fastfetch
    fd
    ffmpeg
    file
    findutils
    fzf
    gawk
    gcc15
    gdb
    gh
    git-lfs
    gitFull
    gnugrep
    gnumake
    gnused
    gnutar
    gparted
    hdparm
    icu
    jq
    linuxHeaders
    lldb
    llvmPackages_21.clang-tools
    llvmPackages_21.clang-unwrapped
    llvmPackages_21.openmp
    lm_sensors
    lsof
    ltrace
    lua
    luajit
    mc
    mypy
    ncdu
    nil
    ninja
    nixd
    nixfmt-rfc-style
    nixpkgs-review
    nodejs
    npm-check
    ntfs3g
    openssh
    openssl
    openssl.dev
    p7zip
    parted
    pciutils
    pkg-config
    psmisc
    ripgrep
    rsync
    ruff
    rust-analyzer
    rustup
    socat
    sqlite
    strace
    sysstat
    tcpdump
    tree
    usbutils
    uv
    uv-sort
    valgrind
    wget
    which
    wireshark
    xz
    yarn
    zip
    zlib
    zstd
  ];

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
  programs.less.enable = true;
  programs.nix-ld.enable = true;
  programs.npm.enable = true;
  programs.obs-studio.enable = true;
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
