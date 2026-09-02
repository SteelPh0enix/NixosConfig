# The one Rust toolchain, shared by the system (`nixos/packages/dev.nix`) and by Neovim
# (`home-manager/nixvim/modules/plugins/rustaceanvim.nix`).
#
# Sharing a single derivation is the whole point: rust-analyzer expands proc macros with
# `$(rustc --print sysroot)/libexec/rust-analyzer-proc-macro-srv`, a binary that ships in the
# *rustc* component and speaks a versioned protocol. Verified on this machine:
#
#   $ rustc --print sysroot
#   /nix/store/...-rust-default-1.98.0
#   $ ls $(rustc --print sysroot)/libexec
#   rust-analyzer-proc-macro-srv
#
# Without the `rust-analyzer` extension below, rustaceanvim falls back to nixpkgs' standalone
# `rust-analyzer` (2026-08-03 = *older* than rustc 1.98.0 here), and the srv protocol version
# can be newer than what that server understands -> "the version of the proc-macro server (N)
# is newer than the version supported by your rust-analyzer (M)", macros stop expanding.
#
# Keeping this in a file both trees import also prevents drift: two `.override` calls with
# different `extensions` lists would produce two store paths, i.e. two toolchains.
#
# `rust-analyzer` is a rustup component (rust-overlay aliases it to `rust-analyzer-preview`;
# the 1.98.0 manifest in the pinned rust-overlay has it) and lands as `<toolchain>/bin`.
{ pkgs }:
pkgs.rust-bin.stable.latest.default.override {
  extensions = [
    "cargo"
    "rust-analysis"
    "rust-analyzer"
    "rust-src"
    "rust-std"
    "rustc"
    "rustfmt"
  ];
}
