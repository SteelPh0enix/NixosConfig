{ pkgs, nixvim, ... }:
{
  imports = [ nixvim.homeModules.default ];

  programs.nixvim = {
    enable = true;

    # Reuse the system package set so nixvim sees this flake's overlays instead of importing
    # its own nixpkgs.
    nixpkgs.pkgs = pkgs;

    # modules/ is written in plain Nixvim option syntax (no `programs.nixvim` prefix), so it is
    # imported *into* the submodule - that also gives those files Nixvim's extended `lib`.
    imports = [ ./modules/configuration.nix ];
  };
}
