{
  pkgs,
  pkgsUnstable,
  nixAiTools,
  ...
}:
{
  home.packages = with pkgs; [
    keepassxc
    chromium
    nixAiTools.packages.${pkgs.system}.crush
  ];

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    package = pkgsUnstable.vscode.fhsWithPackages (
      ps: with ps; [
      ]
    );
  };

  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require('wezterm')
      local config = wezterm.config_builder()

      config.color_scheme = 'Kanagawa (Gogh)'
      config.font_size = 10.5
      config.font = wezterm.font 'BerkeleyMono Nerd Font Mono'
      config.initial_cols = 120
      config.initial_rows = 30
      config.enable_wayland = false

      return config'';
  };

  programs.git = {
    enable = true;
    package = pkgsUnstable.gitFull;
    lfs.enable = true;
    settings = {
      user = {
        name = "Wojciech Olech";
        email = [ "wojciech.olech@n7space.com" ];
        signingKey = "9435CB0C320EFC33";
      };
      core.editor = "nvim";
      merge.ff = true;
      rerere.enabled = true;
      safe.directory = "*";
      pull.rebase = true;
      push = {
        autoSetupRemote = true;
        default = "simple";
      };
      commit.gpgsign = true;
      gpg.format = "openpgp";
    };
  };

  programs.lazygit = {
    enable = true;
    package = pkgsUnstable.lazygit;
    settings = {
      gui = {
        language = "en";
      };
      git = {
        parseEmoji = true;
        overrideGpg = true;
      };
    };
  };

  programs.neovim = {
    defaultEditor = true;
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    withPython3 = true;
    withRuby = true;
  };

  programs.ripgrep = {
    enable = true;
    package = pkgsUnstable.ripgrep;
  };

  programs.fd = {
    enable = true;
    package = pkgsUnstable.fd;
  };

  programs.eza = {
    enable = true;
    package = pkgsUnstable.eza;
    enableFishIntegration = true;
    icons = "always";
    git = true;
  };

  programs.gh.enable = true;
  programs.gh.gitCredentialHelper.enable = true;
}
