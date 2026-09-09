{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Shared with nixvim's rustaceanvim (`rust-toolchain.nix`): the toolchain now carries
    # `bin/rust-analyzer`, so the language server, `cargo` and the proc-macro server are the same
    # release. `nvim` prefixes that same derivation on its PATH (see
    # home-manager/nixvim/modules/plugins/rustaceanvim.nix).
    (import ../../rust-toolchain.nix { inherit pkgs; })

    autoconf
    automake
    cmake
    gcc
    gnumake
    libtool
    ninja
    nixfmt

    pi-coding-agent
    pnpm
    python314
    uv
  ];
}
