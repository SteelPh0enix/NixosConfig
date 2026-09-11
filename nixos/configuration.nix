{
  system.stateVersion = "25.11";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  imports = [
    ./boot.nix
    ./fonts.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./hyprland.nix
    ./locale.nix
    ./nix.nix
    ./nixpkgs.nix
    ./packages
    ./services.nix
    ./shell.nix
    ./users.nix
    ./virtualisation.nix
  ];
}
