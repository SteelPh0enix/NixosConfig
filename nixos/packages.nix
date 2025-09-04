{
  config,
  pkgs,
  nixpkgs-unstable,
  llama-cpp,
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
    (import ./overlays/ccache.nix { cacheDir = config.programs.ccache.cacheDir; })
  ];

  environment.systemPackages = with pkgs; [
    blueman
    btop-rocm
    ccache
    curl
    dotnet-sdk_9
    dotnet-runtime_9
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
    ffmpeg
    file
    findutils
    flaresolverr
    fzf
    gawk
    gh
    git
    git-lfs
    gnugrep
    gnused
    gnutar
    gparted
    hdparm
    icu
    jackett
    jq
    lact
    linuxHeaders
    linuxKernel.packages.linux_zen.cpupower
    lm_sensors
    lsof
    ltrace
    neovim
    nil
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
    pkgsUnstable.llama-cpp
    psmisc
    ripgrep
    rsync
    socat
    strace
    sysstat
    tcpdump
    thermald
    tree
    tree
    usbutils
    wget
    which
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
  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;
  programs.nix-ld.enable = true;
  programs.neovim.withPython3 = true;
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
