{
  pkgs,
  nix-ai-tools,
  nixpkgs-local,
  ...
}:
let
  localNixpkgs = import nixpkgs-local {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{

  home.packages = with pkgs; [
    discord
    keepassxc
    protonvpn-gui
    spotify
    teams-for-linux
    qbittorrent-enhanced
    zenmap
    gimp

    localNixpkgs.stm32cubemx

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

  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "SteelPh0enix";
    userEmail = "wojciech_olech@hotmail.com";
    signing = {
      format = "openpgp";
      key = "141DE12C7B2F574B";
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

  programs.lazygit.enable = true;

  programs.ripgrep.enable = true;
  programs.fd.enable = true;
  programs.eza = {
    enable = true;
    enableFishIntegration = true;
    icons = "always";
    git = true;
  };

  programs.gh.enable = true;
  programs.gh.gitCredentialHelper.enable = true;

  qt.enable = true;
}
