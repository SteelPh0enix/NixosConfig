{ pkgs, nix-ai-tools, ... }:
{
  home.packages = with pkgs; [
    discord
    keepassxc
    protonvpn-gui
    spotify
    teams-for-linux
    qbittorrent-enhanced

    nix-ai-tools.packages.${pkgs.system}.crush
  ];

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
  };

  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require('wezterm')
      local config = wezterm.config_builder()

      config.color_scheme = 'Kanagawa (Gogh)'
      config.font_size = 10.5
      config.font = wezterm.font 'MonaspiceKr NF'
      config.initial_cols = 120
      config.initial_rows = 30
      config.enable_wayland = false

      return config'';
  };

  programs.yt-dlp.enable = true;

  programs.mpv = {
    enable = true;
    package = pkgs.mpv-unwrapped;
    bindings = {
      "n" = "playlist-next";
      "Shift+n" = "add chapter 1";
      "p" = "playlist-prev";
      "Shift+p" = "add chapter -1";
      "s" = "playlist-shuffle";
    };
  };

  qt.enable = true;
}
