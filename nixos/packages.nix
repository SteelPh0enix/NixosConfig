{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    btop
    ccache
    curl
    dmidecode
    dnsutils
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

  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  programs.bat.enable = true;
  programs.ccache.enable = true;
  programs.command-not-found.enable = true;
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
}
