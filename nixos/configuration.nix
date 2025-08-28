{
  pkgs,
  ...
}:
{
  system.stateVersion = "25.05";
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./users.nix
    ./locale.nix
    ./network.nix
  ];
}
