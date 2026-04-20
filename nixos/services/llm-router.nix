{ pkgs, pkgsUnstable, ... }:

let
  llm-router-script = pkgs.writeShellScriptBin "llm-router" ''
    exec ${pkgsUnstable.llama-cpp}/bin/llama-server \
      --models-dir /home/LLMs/llama-models/ \
      --models-preset /home/LLMs/llama-models.ini \
      --host 0.0.0.0 \
      --port 51536 \
      --webui \
      --metrics \
      --props \
      --slots \
      --models-max 2 \
      --parallel 2 \
      --cont-batching \
      --batch-size 4096 \
      --ubatch-size 2048 \
      --threads 16 \
      --threads-batch 8 \
      --prio 2 \
      -ctk q4_0 \
      -ctv q4_0
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
        Environment = [
          "GGML_VK_VISIBLE_DEVICES=0"
          "AMD_VULKAN_ICD=RADV"
        ];
      };

      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
  };
}
