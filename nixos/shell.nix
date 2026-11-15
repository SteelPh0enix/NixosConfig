{ settings, ... }:
{
  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "chromium";
    TERMINAL = "wezterm";
    PI_OFFLINE = "1";
    PI_TELEMETRY = "0";
  };

  environment.localBinInPath = true;

  # `programs.nix-index.enable` is set by the nix-index-database module.
  programs.nix-index-database.comma.enable = true;

  # `flake` exports NH_FLAKE; the hostname is autodetected from networking.hostName, and nh
  # refuses to build on a mismatch.
  programs.nh = {
    enable = true;
    flake = settings.repoPath;

    clean = {
      enable = true;
      dates = "daily";
      extraArgs = "--keep-since 7d";
    };
  };
}
