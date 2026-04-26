{
  system.stateVersion = "25.11";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  imports = [
    ./boot.nix
    ./desktop.nix
    ./fonts.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./locale.nix
    ./nix.nix
    ./packages
    ./services.nix
    ./shell.nix
    ./users.nix
    ./virtualisation.nix
  ];
}
