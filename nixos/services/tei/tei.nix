{ pkgs, ... }:

{
  systemd.services = {
    "tei" = {
      description = "HuggingFace Text Embeddings Inference service (embeddings + reranker)";
      enable = false;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/etc/nixos/nixos/services/tei";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/tei/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/tei/docker-compose.yml down";
      };

      wantedBy = [ "multi-user.target" ];
      wants = [
        "pihole.service"
        "dns-ready.target"
        "network-online.target"
      ];
      after = [
        "pihole.service"
        "dns-ready.target"
        "network-online.target"
      ];
    };
  };
}
