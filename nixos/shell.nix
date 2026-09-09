{ ... }:
{
  environment.sessionVariables = {
    # Nixvim's nvim (home-manager/nixvim/default.nix).
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
    TERMINAL = "wezterm";
    PI_EXTENSION_SEARXNG_INSTANCE = "https://search.steelph0enix.dev/";
    PI_OFFLINE = "1";
    PI_SKIP_VERSION_CHECK = "1";
    PI_TELEMETRY = "0";
  };

  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;
}
