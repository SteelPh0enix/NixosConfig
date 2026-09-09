{ ... }:
{
  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "";
    TERMINAL = "wezterm";
    PI_OFFLINE = "1";
    PI_TELEMETRY = "0";
  };

  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;
}
