{
  pkgs,
  ...
}:
{
  system.stateVersion = "25.05";

  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./users.nix
    ./nix.nix
    ./locale.nix
    ./network.nix
    ./packages.nix
  ];
}
