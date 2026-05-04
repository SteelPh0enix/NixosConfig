{
  config,
  pkgs,
  lib,
  nixvim,
  ...
}:

let
  neovimConfig = import ./modules/configuration.nix {
    inherit
      config
      pkgs
      lib
      nixvim
      ;
  };

  nvim = nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system}.makeNixvimWithModule {
    inherit pkgs;
    module = neovimConfig;
  };

in
{
  home.packages = with pkgs; [
    nvim
  ];

  # Set as default editor for git, etc.
  home.sessionVariables.EDITOR = "${nvim}/bin/nvim";

}
