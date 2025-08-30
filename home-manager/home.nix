{
  home = {
    username = "steelph0enix";
    homeDirectory = "/home/steelph0enix";
    stateVersion = "25.05";
  };

  programs.home-manager.enable = true;

  imports = [
    ./shell.nix
    ./packages.nix
    ./fonts.nix
  ];
}
