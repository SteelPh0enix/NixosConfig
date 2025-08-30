{ ... }:
{
  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
    TERMINAL = "wezterm";

    LLAMA_ARG_HOST = "0.0.0.0";
    LLAMA_ARG_PORT = 51536;
    LLAMA_ARG_BATCH = 2048;
    LLAMA_ARG_UBATCH = 2048;
    LLAMA_ARG_SWA_FULL = 0;
    LLAMA_ARG_KV_SPLIT = 0;
    LLAMA_SET_ROWS = 1; # for LLAMA_ARG_KV_SPLIT=false to work
    LLAMA_ARG_FLASH_ATTN = 1;
    LLAMA_ARG_MLOCK = 1;
    LLAMA_ARG_NO_MMAP = 0;
    LLAMA_ARG_N_GPU_LAYERS = 999;
    LLAMA_OFFLINE = 0;
    LLAMA_ARG_ENDPOINT_SLOTS = 1;
    LLAMA_ARG_ENDPOINT_PROPS = 1;
    UV_TORCH_BACKEND = "auto";
  };

  home.shell.enableFishIntegration = true;
}
