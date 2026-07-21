{ pkgs, ... }:

{
  systemd.services = {
    "anything-llm" = {
      description = "AnythingLLM service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/etc/nixos/nixos/services/anything-llm";
        EnvironmentFile = "/home/anythingllm/.env";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/anything-llm/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/anything-llm/docker-compose.yml down";
      };

      wantedBy = [ "multi-user.target" ];
      wants = [
        "pihole.service"
        "network-online.target"
      ];
      after = [
        "pihole.service"
        "network-online.target"
      ];
    };
  };
}
