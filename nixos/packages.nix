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

    bear
    black
    btop
    ccache
    clang
    clang-tools
    cmake
    colordiff
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
    ffmpeg
    file
    findutils
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
    hdparm
    icu
    jq
    linuxHeaders
    lldb
    lm_sensors
    lsof
    ltrace
    mc
    mypy
    ncdu
    nil
    ninja
    nixd
    nixfmt-rfc-style
    nixpkgs-review
    ntfs3g
    openssh
    openssl
    p7zip
    parted
    pciutils
    psmisc
    ripgrep
    rsync
    ruff
    rust-analyzer
    socat
    strace
    sysstat
    tcpdump
    tree
    usbutils
    uv
    valgrind
    wget
    which
    wireshark
    xz
    zip
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
  programs.lazygit.enable = true;
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
