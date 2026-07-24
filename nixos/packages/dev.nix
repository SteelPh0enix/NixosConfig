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
    basedpyright
    bear
    black
    boost
    clang
    clang-tools
    cmake
    gcc
    gdb
    gnumake
    imagemagick
    isort
    libtool
    libunwind
    libusb1
    lldb
    llvm
    mypy
    nil
    ninja
    nixd
    nixfmt
    nixpkgs-review
    openssl
    pkg-config
    pnpm
    python314
    python314Packages.pyserial
    python314Packages.pytest
    python314Packages.pyusb
    ruff
    texliveFull
    uv
    uv-sort
    valgrind
  ];
}
