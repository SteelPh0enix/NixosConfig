{ pkgs, pkgsUnstable, ... }:

let
  llm-router-script = pkgs.writeShellScriptBin "llm-router" ''
    exec ${pkgsUnstable.llama-cpp}/bin/llama-server \
      --models-dir /home/LLMs/llama-models/ \
      --models-preset /home/LLMs/llama-models.ini \
      --mlock \
      --direct-io \
      --fit on \
      --log-colors on \
      --offline \
      --warmup \
      --host 0.0.0.0 \
      --port 51536 \
      --webui \
      --metrics \
      --props \
      --slots \
      --models-max 1 \
      --parallel 1 \
      --flash-attn on \
      --gpu-layers all
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

      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
  };
}
