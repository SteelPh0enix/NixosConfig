{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    btop-rocm
    bzip3
    cifs-utils
    ddcutil # DDC/CI brightness; Noctalia shells out to it (hardware.i2c)
    dmidecode
    dnsutils
    docker-buildx
    exfatprogs
    fastfetch
    fd
    file
    flac
    gparted
    hdparm
    hyprpicker # colour picker
    inetutils
    jq
    llama-cpp
    lsof
    ltrace
    mc
    minicom
    ncdu
    nerd-font-patcher
    nmap
    ntfs3g
    p7zip
    parallel-full
    parted
    pavucontrol # per-application mixing (Plasma's volume control is gone)
    pciutils
    psmisc
    radeontop
    rar
    remmina
    ripgrep
    socat
    sshfs
    sysstat
    tcpdump
    traceroute
    tree
    uhubctl
    unrar
    usbutils
    wayland-utils
    wdisplays # GUI monitor layout (Hyprland implements wlr-output-management)
    wget
    wl-clipboard
    zip
    unzip
  ];
}
