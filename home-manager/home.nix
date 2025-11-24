{
  home = {
    username = "steelph0enix";
    homeDirectory = "/home/steelph0enix";
    stateVersion = "25.05";
  };

  programs.home-manager.enable = true;

  xdg.configFile."crush/crush.json".source = ./crush.json;

  imports = [
    ./shell.nix
    ./packages.nix
    ./fonts.nix
  ];
}
