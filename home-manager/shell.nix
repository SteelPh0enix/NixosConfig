{ config, ... }:
{
  home.shell.enableFishIntegration = true;
  xdg.configFile."fish/config.fish".source = ./config.fish;
}
