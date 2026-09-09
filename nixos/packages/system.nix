{ pkgs, ... }:
{
  # Admin, hardware and generic CLI utilities (archives, conversion, network, monitoring,
  # clipboard). Per-user applications live in home-manager/packages.nix, build tooling and
  # package managers in dev.nix. `curl findutils gawk gnugrep gnused gnutar rsync strace which
  # xz zstd` are deliberately absent: NixOS puts them in the system profile by itself.
  environment.systemPackages = with pkgs; [
    btop-rocm
    bzip3
    cifs-utils # imperative SMB mounts
    dmidecode
    dnsutils
    docker-buildx
    exfatprogs
    fastfetch
    file
    flac
    gparted
    hdparm
    inetutils # ping
    jq # glue for `curl ... | jq`
    llama-cpp
    lsof
    ltrace
    mc
    minicom
    ncdu
    nerd-font-patcher
    nh
    nmap
    ntfs3g
    p7zip
    parallel-full
    parted
    pciutils
    psmisc
    radeontop
    rar
    remmina
    socat
    sshfs
    sysstat
    tcpdump # setcap wrapper from programs.tcpdump + the `pcap` group
    traceroute
    tree
    uhubctl
    unrar
    usbutils
    wayland-utils # wayland-info
    wget
    wl-clipboard
    xclip
    zip
    unzip
  ];
}
