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
    pavucontrol # per-application mixing
    pciutils
    psmisc
    radeontop
    rar
    remmina
    ripgrep
    socat
    sshfs
    sysstat
    traceroute
    tree
    uhubctl
    unrar
    unzip
    usbutils
    wayland-utils
    wdisplays # GUI monitor layout (niri implements wlr-output-management)
    wget
    wl-clipboard
    zip
  ];
}
