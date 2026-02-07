{
  pkgs,
  nix-ai-tools,
  nixpkgs-unstable,
  ...
}:
let
  pkgsUnstable = import nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  home.packages = with pkgs; [
    firefox
    keepassxc
    protonvpn-gui
    quodlibet-xine-full
    ungoogled-chromium
    zenmap

    nix-ai-tools.packages.${system}.crush
  ];

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    package = pkgsUnstable.vscode.fhsWithPackages (
      ps: with ps; [
        automake
        cmake
        curl
        eslint
        gcc15
        gdb
        gnumake
        icu
        lldb
        llvmPackages_21.clang-tools
        llvmPackages_21.clang-unwrapped
        llvmPackages_21.openmp
        lua
        luajit
        nixd
        nixfmt
        nixpkgs-review
        nodejs
        npm-check
        openssl.dev
        pkg-config
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
        email = [ "phoenixpl@hotmail.com" ];
        signingkey = "/home/steelph0enix/.ssh/gitea.pub";
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
      gpg.format = "ssh";
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

  qt.enable = true;
}
