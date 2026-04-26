{
  pkgs,
  nix-ai-tools,
  ...
}:
{
  home.packages = with pkgs; [
    freecad
    heroic
    keepassxc
    krename
    libreoffice-qt6-fresh
    proton-vpn
    qbittorrent-enhanced
    quodlibet-xine-full
    spotify
    teams-for-linux
    ungoogled-chromium
    zenmap

    drawio
    dxvk
    element-desktop
    gimp
    inkscape-with-extensions
    javaPackages.compiler.temurin-bin.jdk-25
    jellyfin-media-player
    obsidian
    orca-slicer
    prismlauncher
    protontricks
    protonup-qt
    stm32cubemx
    winePackages.stagingFull
    winetricks
    xournalpp

    nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.crush
  ];

  programs.git = {
    enable = true;
    lfs = {
      enable = true;
    };
    package = pkgs.gitFull;
    settings = {
      user = {
        name = "SteelPh0enix";
        email = "wojciech_olech@hotmail.com";
        signingkey = "141DE12C7B2F574B";
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

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    package = pkgs.vscode.fhsWithPackages (
      ps: with ps; [
        automake
        curl
        eslint
        gcc15
        gdb
        gnumake
        icu
        lldb
        llvmPackages.clang-unwrapped
        lua
        luajit
        nixd
        nixfmt
        nixpkgs-review
        nodejs
        npm-check
        openssl.dev
        pkg-config
        pkgs.clang-tools
        pkgs.cmake
        pkgs.git-lfs
        pkgs.gitFull
        pkgs.ninja
        pkgs.ruff
        pkgs.uv
        pkgs.uv-sort
        rustup
        sqlite
        wget
        yarn
        zlib
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
      config.font = wezterm.font_with_fallback { 'BerkeleyMono Nerd Font Mono' }
      config.initial_cols = 120
      config.initial_rows = 30
      config.enable_wayland = false

      return config'';
  };

  programs.yt-dlp = {
    enable = true;
  };

  programs.mpv = {
    enable = true;

    package = pkgs.mpv.override {
      mpv-unwrapped = pkgs.mpv-unwrapped.override {
        waylandSupport = true;
        jackaudioSupport = true;
        ffmpeg = pkgs.ffmpeg-full;
      };
      scripts = with pkgs.mpvScripts; [
        sponsorblock
        thumbnail
        thumbfast
        autosub
        uosc
      ];
    };

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
