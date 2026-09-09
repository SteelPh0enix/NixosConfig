{ ... }:
{
  home = {
    username = "steelph0enix";
    homeDirectory = "/home/steelph0enix";
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;

  imports = [
    ./options.nix
    ./shell.nix
    ./packages.nix
    ./fonts.nix
    ./nonfree-fonts.nix
    ./nixvim
  ];
}
