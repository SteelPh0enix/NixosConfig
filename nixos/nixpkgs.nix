{ inputs, ... }:
{
  nixpkgs.config = import ../nix/nixpkgs-config.nix;
  nixpkgs.overlays = import ../nix/overlays.nix inputs;
}
