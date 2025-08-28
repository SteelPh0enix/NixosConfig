{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gedit
    keepassxc
    protonvpn-gui
    teams-for-linux
    vscode
    wezterm
  ];
}
