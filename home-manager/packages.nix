{ pkgs, ... }:
{
  home.packages = with pkgs; [
    keepassxc
    obsidian
    quodlibet-xine-full
    ungoogled-chromium
  ];

  programs.vscode = {
    enable = true;
    # FHS env for the language plugins: shared build tools from nix/dev-tools.nix plus the
    # per-language bits.
    package = pkgs.vscode.fhsWithPackages (
      ps:
      import ../nix/dev-tools.nix ps
      ++ (with ps; [
        clang-tools
        curl
        eslint
        gdb
        git-lfs
        gitFull
        icu
        lldb
        llvmPackages.clang-unwrapped
        lua
        luajit
        nixd
        nixpkgs-review
        nodejs
        npm-check
        openssl.dev
        pkg-config
        ruff
        rustup
        sqlite
        uv-sort
        wget
        yarn
        zlib
      ])
    );
  };

  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require('wezterm')
      local config = wezterm.config_builder()

      config.color_scheme = 'Afterglow (Gogh)'
      config.font_size = 10.5
      config.font = wezterm.font_with_fallback { 'Berkeley Mono', 'Symbols Nerd Font Mono' }
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
        signingkey = "/home/steelph0enix/.ssh/forgejo.pub";
      };
      core.editor = "nvim";
      merge.ff = true;
      rerere.enabled = true;
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

  programs.eza = {
    enable = true;
    icons = "always";
    git = true;
    # -g list group, -M show mount details. Shell integration maps `ls` onto eza.
    extraOptions = [ "-gM" ];
  };

  programs.gh.enable = true;
  programs.gh.gitCredentialHelper.enable = true;

  qt.enable = true;
}
