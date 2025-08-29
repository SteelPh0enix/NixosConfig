{ pkgs, pkgs-unstable, ... }:
{
  environment.systemPackages = with pkgs; [
    # development
    automake
    cargo
    ccache
    cmake
    gcc
    gdb
    gnumake
    linuxHeaders
    pkgs-unstable.llama-cpp-rocm
    lldb
    llvmPackages.clangWithLibcAndBasicRtAndLibcxx
    llvmPackages.openmp
    meson
    mpi
    nixfmt-rfc-style
    python3Full
    rustc

    # linux tools
    btop
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
    lm_sensors
    lsof
    ltrace
    neovim
    nmap
    ntfs3g
    openssl
    p7zip
    parted
    pciutils
    psmisc
    ripgrep
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

  qt.enable = true;
  qt.platformTheme = "gnome";
  qt.style = "adwaita-dark";

  programs.fish.shellAliases = {
    ls = "eza";
    l = "eza -lh";
    la = "eza -alh";
    lg = "lazygit";
    e = "$EDITOR";
    eh = "$EDITOR .";
    pkgu = "sudo nixos-rebuild switch --flake .#steelph0enix-pc --upgrade-all";
  };
}
