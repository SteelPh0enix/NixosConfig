# The one Rust toolchain (`pkgs.rustToolchain`), used by nixos/packages/dev.nix,
# nixvim's rustaceanvim and the flake devShell.
#
# Sharing a single derivation matters: rust-analyzer expands proc macros through
# `$(rustc --print sysroot)/libexec/rust-analyzer-proc-macro-srv`, a binary shipped by the
# toolchain's own `rustc` component. nixpkgs' standalone `rust-analyzer` trails the toolchain
# release, and a newer srv protocol than the server understands = macros stop expanding.
final: prev: {
  rustToolchain = prev.rust-bin.stable.latest.default.override {
    extensions = [
      "rust-analyzer"
      "rust-src"
    ];
  };
}
