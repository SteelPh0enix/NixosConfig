{
  pkgs,
  ...
}:
{
  system.stateVersion = "25.05";

  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./mounts.nix
    ./users.nix
    ./nix.nix
    ./locale.nix
    ./packages.nix
    ./services.nix
    ./fonts.nix
  ];
}
