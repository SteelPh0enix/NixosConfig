{ pkgs, ... }:
{
  environment.systemPackages =
    with pkgs;
    [
      # nixpkgs ships these from one rustc release. rust-analyzer carries its own
      # proc-macro server and points RUST_SRC_PATH at the standard library sources.
      cargo
      clippy
      rust-analyzer
      rustc
      rustfmt
    ]
    ++ import ../../nix/dev-tools.nix pkgs
    ++ [
      imagemagick
      openspec
      pnpm
      python314
    ];
}
