{
  system.stateVersion = "25.05";
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
    ./mounts.nix
    ./networking.nix
    ./nix.nix
    ./nixpkgs.nix
    ./packages
    ./services.nix
    # `./services` would resolve to ./services.nix, so name the directory entry explicitly.
    ./services/default.nix
    ./shell.nix
    ./timers.nix
    ./users.nix
    ./virtualisation.nix
  ];
}
