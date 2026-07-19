{
  nixvim,
  ...
}:
{
  home = {
    username = "steelph0enix";
    homeDirectory = "/home/steelph0enix";
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;

  imports = [
    nixvim.homeModules.nixvim
    ./shell.nix
    ./packages.nix
    ./fonts.nix
    ./opencode.nix
    ./nixvim
  ];
}
