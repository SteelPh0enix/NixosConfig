{
  pkgs,
  ...
}:
{
  system.stateVersion = "25.05";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
    ./desktop.nix
  ];
}
