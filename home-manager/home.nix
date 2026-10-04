{ settings, ... }:
{
  home = {
    username = settings.userName;
    homeDirectory = "/home/${settings.userName}";
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;

  imports = [
    ./shell.nix
    ./packages.nix
    ./fonts.nix
    ./nonfree-fonts.nix
    ./hyprland
    ./nixvim
    ./pi
    ./theming.nix
    ./flashpoint.nix
    ./vesktop.nix
    ./xdg.nix
  ];
}
