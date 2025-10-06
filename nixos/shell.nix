{ pkgs, ... }:
{
  environment.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
    TERMINAL = "wezterm";

    LLAMA_ARG_HOST = "0.0.0.0";
    LLAMA_ARG_PORT = 51536;
    LLAMA_ARG_FLASH_ATTN = "on";
    LLAMA_ARG_MLOCK = 1;
    LLAMA_ARG_NO_MMAP = 1;
    LLAMA_ARG_N_GPU_LAYERS = 999;
    LLAMA_OFFLINE = 0;
    LLAMA_ARG_ENDPOINT_SLOTS = 1;
    LLAMA_ARG_ENDPOINT_PROPS = 1;
    LLAMA_ARG_CONTEXT_SHIFT = 1;
    UV_TORCH_BACKEND = "auto";

    GST_PLUGIN_SYSTEM_PATH_1_0 = "${pkgs.gst_all_1.gstreamer.out}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-good}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-bad}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-ugly}/lib/gstreamer-1.0";
  };

  programs.fish.shellInit = builtins.readFile ./init.fish;
  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;

  users.motd = "hi $USER";
}
