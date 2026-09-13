{
  pkgs,
  settings,
  ...
}:

let
  # Plain runtime path into the working checkout, not a store path: edit the preset and
  # `systemctl restart llm-router` - no rebuild.
  modelsPreset = "${settings.repoPath}/nixos/services/llm-router/llama-server.ini";

  llm-router-script = pkgs.writeShellScriptBin "llm-router" ''
    exec ${pkgs.llama-cpp}/bin/llama-server \
      --models-preset ${modelsPreset} \
      --host 0.0.0.0 \
      --port 51536 \
      --models-max 4 \
      --webui \
      --metrics \
      --props \
      --slots \
      --perf
  '';
in
{
  systemd.services = {
    "llm-router" = {
      description = "LLM Router service - Multi-model llama-server";
      enable = true;

      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/home/steelph0enix/LLMs";
        ExecStart = "${llm-router-script}/bin/llm-router";
        Restart = "on-failure";
        RestartSec = 10;
        User = "steelph0enix";
        Group = "users";
        LimitMEMLOCK = "infinity";
      };

      environment = {
        GGML_VK_ALLOW_GRAPHICS_QUEUE = "1";
        # llvmpipe is enumerated as a second Vulkan device; pin the real one.
        GGML_VK_VISIBLE_DEVICES = "0";
      };

      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
  };
}
