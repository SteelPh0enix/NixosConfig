{
  config,
  pkgs,
  pkgsUnstable,
  rust-overlay,
  ...
}:
let
  pkgsUnstable' = pkgsUnstable.extend (import ./overlays/llama-cpp.nix);
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

    # pkgsUnstable.llama-cpp
    bear
    blueman
    boost
    bzip3
    ccache
    cifs-utils
    clang
    cpupower-gui
    dmidecode
    dnsutils
    docker
    docker-buildx
    exfatprogs
    figlet
    file
    findutils
    flac
    gawk
    gcc
    gdb
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
    pkgsUnstable.curl
    pkgsUnstable.eza
    pkgsUnstable.fastfetch
    pkgsUnstable.fd
    pkgsUnstable.ffmpeg-full
    pkgsUnstable.flatpak
    pkgsUnstable.fzf
    pkgsUnstable.jq
    pkgsUnstable.mc
    pkgsUnstable.ncdu
    pkgsUnstable.nerd-font-patcher
    pkgsUnstable.nil
    pkgsUnstable.ninja
    pkgsUnstable.nixd
    pkgsUnstable.nixfmt
    pkgsUnstable.nixpkgs-review
    pkgsUnstable.radeontop
    pkgsUnstable.ripgrep
    pkgsUnstable.sqlite
    pkgsUnstable.tree
    pkgsUnstable.uv
    pkgsUnstable.valgrind
    pkgsUnstable.vkd3d
    pkgsUnstable.wget
    psmisc
    rar
    rsync
    socat
    sshfs
    strace
    sysstat
    tcpdump
    texliveFull
    thermald
    traceroute
    unrar
    unzip
    usbutils
    vk-bootstrap
    vkdevicechooser
    vkdisplayinfo
    vkmark
    vulkan-extension-layer
    vulkan-helper
    vulkan-tools
    vulkan-utility-libraries
    websocat
    which
    wireguard-tools
    xz
    zenity
    zip
    zstd
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
