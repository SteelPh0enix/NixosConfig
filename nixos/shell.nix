{ pkgs, ... }:
{
  environment.sessionVariables = {
    EDITOR = "code";
    VISUAL = "code";
    BROWSER = "firefox";
    TERMINAL = "wezterm";

    OPENAI_API_KEY = "llamacpp";
    OPENAI_BASE_URL = "http://127.0.0.1:51536/v1";

    GST_PLUGIN_SYSTEM_PATH_1_0 = pkgs.lib.makeSearchPathOutput "out" "lib/gstreamer-1.0" [
      pkgs.gst_all_1.gstreamer
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gst-plugins-good
      pkgs.gst_all_1.gst-plugins-bad
      pkgs.gst_all_1.gst-plugins-ugly
    ];

    PI_OFFLINE = "1";
    PI_SKIP_VERSION_CHECK = "1";
    PI_TELEMETRY = "0";
  };

  programs.fish.shellInit = builtins.readFile ./init.fish;
  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;
}
