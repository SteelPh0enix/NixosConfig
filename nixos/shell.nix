{ settings, ... }:
{
  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
    TERMINAL = "wezterm";
    PI_OFFLINE = "1";
    PI_SKIP_VERSION_CHECK = "1";
    PI_TELEMETRY = "0";
  };

  # ~/.local/bin for every login shell, without going through home-manager's xdg options.
  environment.localBinInPath = true;

  # `programs.nix-index.enable` is set by the nix-index-database module.
  programs.nix-index-database.comma.enable = true;

  # nh is the OS manager: `flake` exports NH_FLAKE, so `nh os switch` needs no path, and the
  # hostname is autodetected from networking.hostName.
  programs.nh = {
    enable = true;
    flake = settings.repoPath;

    # Replaces nix.gc (enabling both makes the nh module warn).
    clean = {
      enable = true;
      dates = "daily";
      # Keeps >= 1 generation by default; --optimise is unnecessary, auto-optimise-store covers it.
      extraArgs = "--keep-since 7d";
    };
  };
}
