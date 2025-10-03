{ pkgs, ... }:
{
  environment.shellAliases = {
    ls = "eza --icons=always -gM --git";
    l = "ls -lh";
    la = "ls -alh";
    lg = "lazygit";
    e = "$EDITOR";
    eh = "$EDITOR .";
    cpr = "cp -r";
    os-rebuild = "cd ~/nixos-config && sudo nixos-rebuild switch --flake .#RX-78-FPC --upgrade-all --print-build-logs --show-trace --refresh";
    os-update = "cd ~/nixos-config && nix flake update && os-rebuild && git add flake.lock && git commit -m 'os update'";
    os-clean = "sudo nix-store --gc && sudo nix-store --optimise && sudo nix-collect-garbage -d && nix-collect-garbage -d";
    rbt = "sudo systemctl reboot";
    cfge = "code ~/nixos-config";
    docker-here = "docker run --rm -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)";
    docker-here-shell = "docker run --rm -it -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)";
    docker-here-rocm = "docker run --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --rm";
    docker-here-shell-rocm = "docker run --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --rm -it";
  };

  environment.sessionVariables = {
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
    LLAMA_ARG_FLASH_ATTN = "on";
    LLAMA_ARG_MLOCK = 1;
    LLAMA_ARG_NO_MMAP = 0;
    LLAMA_ARG_N_GPU_LAYERS = 999;
    LLAMA_OFFLINE = 0;
    LLAMA_ARG_ENDPOINT_SLOTS = 1;
    LLAMA_ARG_ENDPOINT_PROPS = 1;
    LLAMA_ARG_CONTEXT_SHIFT = 1;
    LLAMA_ARG_NO_CONTEXT_SHIFT = 0;
    UV_TORCH_BACKEND = "auto";

    GST_PLUGIN_SYSTEM_PATH_1_0 = "${pkgs.gst_all_1.gstreamer.out}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-good}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-bad}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-ugly}/lib/gstreamer-1.0";
  };

  programs.fish.shellInit = builtins.readFile ./init.fish;
  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;
}
