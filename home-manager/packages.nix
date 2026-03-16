{
  pkgs,
  pkgsUnstable,
  nix-ai-tools,
  ...
}:
{
  home.packages = with pkgs; [
    freecad
    keepassxc
    krename
    libreoffice-qt6-fresh
    protonvpn-gui
    qbittorrent-enhanced
    quodlibet-xine-full
    spotify
    ungoogled-chromium
    zenmap

    pkgsUnstable.drawio
    pkgsUnstable.dxvk
    pkgsUnstable.element-desktop
    pkgsUnstable.gimp
    heroic
    pkgsUnstable.inkscape-with-extensions
    pkgsUnstable.javaPackages.compiler.temurin-bin.jdk-25
    pkgsUnstable.jellyfin-media-player
    pkgsUnstable.orca-slicer
    pkgsUnstable.prismlauncher
    pkgsUnstable.protontricks
    pkgsUnstable.protonup-qt
    pkgsUnstable.stm32cubemx
    teams-for-linux
    pkgsUnstable.vkd3d
    pkgsUnstable.winePackages.stagingFull
    pkgsUnstable.winetricks

    nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.crush
  ];

  programs.git = {
    enable = true;
    lfs = {
      enable = true;
      package = pkgsUnstable.git-lfs;
    };
    package = pkgsUnstable.gitFull;
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

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    package = pkgsUnstable.vscode.fhsWithPackages (
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
        pkgsUnstable.clang-tools
        pkgsUnstable.cmake
        pkgsUnstable.git-lfs
        pkgsUnstable.gitFull
        pkgsUnstable.ninja
        pkgsUnstable.ruff
        pkgsUnstable.uv
        pkgsUnstable.uv-sort
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
    package = pkgsUnstable.wezterm;
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
    package = pkgsUnstable.yt-dlp;
  };

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
    package = pkgsUnstable.eza;
    enable = true;
    enableFishIntegration = true;
    icons = "always";
    git = true;
  };

  programs.gh.enable = true;
  programs.gh.gitCredentialHelper.enable = true;

  qt.enable = true;
}
