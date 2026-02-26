{
  pkgs,
  nix-ai-tools,
  nixpkgs-unstable,
  ...
}:
let
  pkgsUnstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  home.packages = with pkgs; [
    keepassxc
    chromium
    nix-ai-tools.packages.${pkgs.system}.crush
  ];

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    package = pkgsUnstable.vscode.fhsWithPackages (
      ps: with ps; [
        automake
        curl
        dotnetCorePackages.runtime_9_0-bin
        dotnetCorePackages.sdk_9_0-bin
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
        pkgsUnstable.glibc
        pkgsUnstable.glibc
        pkgsUnstable.ninja
        pkgsUnstable.ruff
        pkgsUnstable.uv
        pkgsUnstable.uv-sort
        pkgsUnstable.yarn
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

  qt.enable = true;
}
