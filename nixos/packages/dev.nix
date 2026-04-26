{ pkgs, pkgsUnstable, ... }:
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
    linuxKernel.packages.linux_zen.cpupower
    lldb
    openssh
    openssl
    texliveFull

    pkgsUnstable.basedpyright
    pkgsUnstable.black
    pkgsUnstable.clang-tools
    pkgsUnstable.cmake
    pkgsUnstable.isort
    pkgsUnstable.mypy
    pkgsUnstable.nil
    pkgsUnstable.ninja
    pkgsUnstable.nixd
    pkgsUnstable.nixfmt
    pkgsUnstable.nixpkgs-review
    pkgsUnstable.python314
    pkgsUnstable.python314Packages.pyserial
    pkgsUnstable.python314Packages.pytest
    pkgsUnstable.python314Packages.pyusb
    pkgsUnstable.ruff
    pkgsUnstable.valgrind
  ];
}
