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
  home.packages = [
    nvim
  ];
}
