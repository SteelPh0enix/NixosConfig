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
    clang
    gcc
    gdb
    gnumake
    libtool
    libunwind
    libusb1
    linuxHeaders
    lldb
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
    pkg-config
    python314
    python314Packages.pyserial
    python314Packages.pytest
    python314Packages.pyusb
    ruff
    uv
    uv-sort
    valgrind
  ];
}
