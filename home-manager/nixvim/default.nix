{ pkgs, nixvim, ... }:
{
  imports = [ nixvim.homeModules.default ];

  programs.nixvim = {
    enable = true;

    # Reuse the system package set so nixvim sees this flake's overlays.
    nixpkgs.pkgs = pkgs;

    # modules/ uses plain Nixvim syntax and Nixvim's extended lib.
    imports = [ ./modules/configuration.nix ];
  };
}
