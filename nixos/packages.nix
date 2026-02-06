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
    btop
    colordiff
    dmidecode
    dnsutils
    docker
    docker-buildx
    dotnetCorePackages.runtime_9_0-bin
    dotnetCorePackages.sdk_9_0-bin
    exfat
    exfatprogs
    fastfetch
    file
    findutils
    gawk
    gcc15
    gdb
    gh
    gnugrep
    gnumake
    gnused
    gnutar
    gparted
    hdparm
    icu
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
    ncurses5
    nil
    nixd
    nixfmt
    nixpkgs-review
    nodejs
    npm-check
    ntfs3g
    openssh
    openssl
    openssl.dev
    parted
    pciutils
    pkg-config
    pkgsUnstable.black
    pkgsUnstable.cmake
    pkgsUnstable.curl
    pkgsUnstable.eslint
    pkgsUnstable.eza
    pkgsUnstable.fd
    pkgsUnstable.ffmpeg
    pkgsUnstable.fzf
    pkgsUnstable.jq
    pkgsUnstable.ninja
    pkgsUnstable.p7zip
    pkgsUnstable.ripgrep
    pkgsUnstable.ruff
    pkgsUnstable.uv
    pkgsUnstable.uv-sort
    psmisc
    rsync
    rust-analyzer
    rustup
    socat
    sqlite
    sshpass
    strace
    sysstat
    tree
    usbutils
    valgrind
    wget
    which
    xz
    yarn
    zip
    zlib
    zstd
  ];

  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

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
  programs.firefox.enable = true;

  programs.fish = {
    package = pkgsUnstable.fish;
    enable = true;
  };

  programs.fzf = {
    fuzzyCompletion = true;
    keybindings = true;
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    package = pkgsUnstable.gitFull;
  };

  programs.gnupg.agent = {
    enable = true;
    enableBrowserSocket = true;
  };

  programs.java = {
    enable = true;
    binfmt = true;
  };

  programs.less = {
    enable = true;
    package = pkgsUnstable.less;
  };

  programs.nix-ld.enable = true;
  programs.npm.enable = true;
  programs.obs-studio.enable = true;
  programs.screen.enable = true;
  programs.ssh.startAgent = true;
  programs.tcpdump.enable = true;

  programs.wireshark = {
    enable = true;
    dumpcap.enable = true;
    usbmon.enable = true;
  };

  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];

  qt.enable = true;
}
