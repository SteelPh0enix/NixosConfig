{ pkgs, nixvim, ... }:
{
  imports = [ nixvim.homeModules.default ];

  programs.nixvim = {
    enable = true;

    # Reuse the system package set, otherwise nixvim imports its own nixpkgs without this
    # flake's overlays and `rust-bin` (rust-toolchain.nix) would not resolve.
    nixpkgs.pkgs = pkgs;

    # modules/ is written in plain Nixvim option syntax (no `programs.nixvim` prefix), so it is
    # imported *into* the submodule - that also gives those files Nixvim's extended `lib`.
    imports = [ ./modules/configuration.nix ];
  };
}
