# The one Rust toolchain, shared by the system (`nixos/packages/dev.nix`) and by Neovim
# (`home-manager/nixvim/modules/plugins/rustaceanvim.nix`).
#
# Sharing a single derivation is the whole point: rust-analyzer expands proc macros with
# `$(rustc --print sysroot)/libexec/rust-analyzer-proc-macro-srv`, a binary that ships in the
# *rustc* component and speaks a versioned protocol:
#
#   rustc --print sysroot
#   ls $(rustc --print sysroot)/libexec   # -> rust-analyzer-proc-macro-srv
#
# Without the `rust-analyzer` extension below, rustaceanvim falls back to nixpkgs' standalone
# `rust-analyzer`, which trails the toolchain release - the srv protocol can then be newer than
# what that server understands -> "the version of the proc-macro server (N) is newer than the
# version supported by your rust-analyzer (M)", macros stop expanding.
#
# Keeping this in a file both trees import also prevents drift: two `.override` calls with
# different `extensions` lists would produce two store paths, i.e. two toolchains.
#
# The `default` profile already carries rustc/cargo/clippy/rustfmt/rust-std and `rust-docs`
# (the offline HTML docs, ~700 MiB), so only the two extras are listed. `rust-analysis` is
# `rustc --analyze` data, unrelated to rust-analyzer.
{ pkgs }:
pkgs.rust-bin.stable.latest.default.override {
  extensions = [
    "rust-analyzer"
    "rust-src"
  ];
}
