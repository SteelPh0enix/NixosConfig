{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gedit
    keepassxc
    protonvpn-gui
    teams-for-linux
    wezterm
    spotify
    discord
  ];

  programs.uv.enable = true;
  programs.vscode.enable = true;
  programs.wezterm.enable = true;
  programs.wezterm.extraConfig = ''
    local wezterm = require('wezterm')
    local config = wezterm.config_builder()

    config.color_scheme = 'Kanagawa (Gogh)'
    config.font_size = 10.5
    config.font = wezterm.font 'MonaspiceKr NF'
    config.initial_cols = 120
    config.initial_rows = 30

    return config'';
  programs.yt-dlp.enable = true;

  qt.enable = true;
}
