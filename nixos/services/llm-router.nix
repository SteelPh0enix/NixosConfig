{ pkgs, ... }:

let
  llm-router-script = pkgs.writeShellScriptBin "llm-router" ''
    exec ${pkgs.llama-cpp}/bin/llama-server \
      --models-dir /home/LLMs/models/ \
      --models-preset /home/LLMs/llama-server.ini \
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
      };

      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
  };
}
