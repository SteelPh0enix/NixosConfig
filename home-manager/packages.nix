{ pkgs, nix-ai-tools, ... }:
{
  home.packages = with pkgs; [
    keepassxc
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

  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "Wojciech Olech";
    userEmail = "wojciech.olech@n7space.com";
    signing = {
      format = "openpgp";
      key = "9435CB0C320EFC33";
      signByDefault = true;
    };

    extraConfig = {
      core.editor = "nvim";
      merge.ff = true;
      rerere.enabled = true;
      safe.directory = "*";
      pull.rebase = true;
      push = {
        autoSetupRemote = true;
        default = "simple";
      };
    };
  };

  qt.enable = true;
}
