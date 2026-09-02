{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Shared with nixvim's rustaceanvim (`rust-toolchain.nix`): the toolchain now carries
    # `bin/rust-analyzer`, so the language server, `cargo` and the proc-macro server are the
    # same release. `nvim` prefixes that same derivation on its PATH (see
    # home-manager/nixvim/modules/plugins/rustaceanvim.nix).
    (import ../../rust-toolchain.nix { inherit pkgs; })

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
    # nil: dropped purely as dead weight - nixd is the Nix server (plugins/lsp.nix) and nothing
    # else uses it. Note this does *not* change the `nil_ls`-on-`:lsp enable` surprise recorded
    # in lsp.nix: that config is registered by nvim-lspconfig's runtime `lsp/nil_ls.lua`
    # regardless of whether the binary exists (it just fails to spawn now).
    ninja
    nixd
    nixfmt
    nixpkgs-review
    openspec
    openssl
    pi-coding-agent
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
