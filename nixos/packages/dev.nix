{ pkgs, ... }:
{
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

    autoconf
    automake
    bear
    boost
    ccache
    clang
    gcc
    gdb
    gnumake
    libtool
    libunwind
    libusb1
    linuxHeaders
    pkgs.linuxPackages.cpupower
    lldb
    openssh
    openssl
    texliveFull

    basedpyright
    black
    clang-tools
    cmake
    isort
    mypy
    nil
    ninja
    nixd
    nixfmt
    nixpkgs-review
    python314
    python314Packages.pyserial
    python314Packages.pytest
    python314Packages.pyusb
    ruff
    valgrind
  ];
}
