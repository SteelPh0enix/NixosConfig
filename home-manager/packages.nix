{
  pkgs,
  nix-ai-tools,
  ...
}:
{
  home.packages = with pkgs; [
    keepassxc
    proton-vpn
    quodlibet-xine-full
    ungoogled-chromium
    zenmap
  ];

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
        nodejs
        npm-check
        openssl.dev
        pkg-config
        rustup
        sqlite
        wget
        yarn
        zlib
        clang-tools
        cmake
        git-lfs
        gitFull
        ninja
        ruff
        uv
        uv-sort
      ]
    );
  };

  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require('wezterm')
      local config = wezterm.config_builder()

      config.color_scheme = 'Afterglow (Gogh)'
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


  programs.git = {
    enable = true;
    lfs = {
      enable = true;
    };
    package = pkgs.gitFull;
    settings = {
      user = {
        name = "SteelPh0enix";
        email = [ "wojciech_olech@hotmail.com" ];
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
