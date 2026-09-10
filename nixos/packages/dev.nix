{ pkgs, ... }:
{
  environment.systemPackages =
    with pkgs;
    [
      # The toolchain carries `bin/rust-analyzer`, so the language server, `cargo` and the
      # proc-macro server are one release (see nix/overlays/rust-toolchain.nix; nixvim's
      # rustaceanvim uses the same `pkgs.rustToolchain`).
      rustToolchain
    ]
    ++ import ../../nix/dev-tools.nix pkgs
    ++ [
      pi-coding-agent
      pnpm
      python314
    ];
}
