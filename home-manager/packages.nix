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
    freecad

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

    package = (
      pkgs.mpv-unwrapped.wrapper {
        scripts = with pkgs.mpvScripts; [
          sponsorblock
          thumbnail
          thumbfast
          autosub
          uosc
        ];

        mpv = pkgs.mpv-unwrapped.override {
          waylandSupport = true;
          jackaudioSupport = true;
          ffmpeg = pkgs.ffmpeg-full;
        };
      }
    );

    config = {
      osc = "no";
      osd-bar = "no";
      border = "no";
      osd-on-seek = "no";
      profile = "high-quality";
      script-opts = "osc-visibility=never";
      ytdl-format = "bestvideo+bestaudio";
      video-sync = "display-resample";
    };

    bindings = {
      "tab" = "script-binding uosc/toggle-ui";
      "n" = "script-binding uosc/next";
      "Shift+n" = "add chapter 1";
      "p" = "script-binding uosc/prev";
      "Shift+p" = "add chapter -1";
      "s" = "script-binding uosc/shuffle";
      "Shift+S" = "script-binding uosc/subtitles";
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
