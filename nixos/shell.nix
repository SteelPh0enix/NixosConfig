{ pkgs, ... }:
{
  environment.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "";
    TERMINAL = "wezterm";
    OPENAI_API_KEY="***";
    OPENAI_BASE_URL = "http://steelph0enix.framework:51536/v1";
    PI_EXTENSION_SEARXNG_INSTANCE = "https://search.steelph0enix.dev/";

    GST_PLUGIN_SYSTEM_PATH_1_0 = pkgs.lib.makeSearchPathOutput "out" "lib/gstreamer-1.0" [
      pkgs.gst_all_1.gstreamer
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gst-plugins-good
      pkgs.gst_all_1.gst-plugins-bad
      pkgs.gst_all_1.gst-plugins-ugly
    ];
  };

  programs.fish.shellInit = builtins.readFile ./init.fish;
  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;
}
