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
    boost
    clang
    clang-tools
    cmake
    gcc
    gdb
    gnumake
    libtool
    libunwind
    libusb1
    lldb
    llvm
    nil
    ninja
    nixd
    nixfmt
    nixpkgs-review
    openssl
    pi-coding-agent
    pnpm
    python314
    python314Packages.pyserial
    python314Packages.pytest
    python314Packages.pyusb
    ruff
    texliveFull
    valgrind
  ];
}
