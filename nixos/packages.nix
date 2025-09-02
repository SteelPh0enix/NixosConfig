{
  config,
  pkgs,
  nixpkgs-unstable,
  llama-cpp,
  ...
}:
let
  llamaPkgs = import nixpkgs-unstable {
    overlays = [
      (llama-cpp.overlays.default)
      (self: super: {
        ccacheWrapper = super.ccacheWrapper.override {
          extraConfig = ''
            export CCACHE_COMPRESS=1
            export CCACHE_DIR="${config.programs.ccache.cacheDir}"
            export CCACHE_UMASK=007
            export CCACHE_SLOPPINESS=random_seed
            if [ ! -d "$CCACHE_DIR" ]; then
              echo "====="
              echo "Directory '$CCACHE_DIR' does not exist"
              echo "Please create it with:"
              echo "  sudo mkdir -m0770 '$CCACHE_DIR'"
              echo "  sudo chown root:nixbld '$CCACHE_DIR'"
              echo "====="
              exit 1
            fi
            if [ ! -w "$CCACHE_DIR" ]; then
              echo "====="
              echo "Directory '$CCACHE_DIR' is not accessible for user $(whoami)"
              echo "Please verify its access permissions"
              echo "====="
              exit 1
            fi
          '';
        };
      })
      (self: super: {
        llama-cpp = llamaPkgs.llamaPackages.llama-cpp.override {
          llamaVersion = "1.2.3";
          stdenv = super.ccacheStdenv;
          buildAllCudaFaQuants = true;
          useMpi = true;
        };
      })
    ];
    system = pkgs.system;
    config.allowUnfree = true;
    config.rocmSupport = true;
    config.rocmGpuTargets = "gfx1100";
  };
in
{
  environment.systemPackages = with pkgs; [
    llamaPkgs.llama-cpp
    lact
    btop-rocm
    ccache
    curl
    dmidecode
    dnsutils
    docker
    docker-buildx
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
    git
    git-lfs
    gnugrep
    gnused
    gnutar
    gparted
    hdparm
    jq
    linuxHeaders
    lm_sensors
    lsof
    ltrace
    neovim
    nil
    nix-direnv
    nixd
    nixfmt-rfc-style
    nmap
    ntfs3g
    openssl
    p7zip
    parted
    pciutils
    psmisc
    ripgrep
    rsync
    socat
    strace
    sysstat
    tcpdump
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
  programs.cpu-energy-meter.enable = true;
  programs.dconf.enable = true;
  programs.direnv = {
    enable = true;
    enableFishIntegration = true;
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
