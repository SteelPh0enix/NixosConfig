{ config, pkgs, ... }:
{
  nixpkgs.overlays = [
    (import ./overlays/ccache.nix { cacheDir = config.programs.ccache.cacheDir; })
  ];

  environment.systemPackages = with pkgs; [
    btop
    ccache
    dotnet-sdk_9
    dotnet-runtime_9
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
    icu
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

  environment.sessionVariables = {
    DOTNET_ROOT = "${pkgs.dotnet-sdk_9}/share/dotnet/";
  };

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
  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;
  programs.nix-ld.enable = true;
  programs.neovim.withPython3 = true;
  programs.npm.enable = true;
  programs.obs-studio.enable = true;
  programs.screen.enable = true;
  programs.ssh.startAgent = true;
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
