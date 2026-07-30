{ pkgs, ... }:

{
  systemd.services = {
    "hindsight" = {
      description = "Hindsight memory service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/etc/nixos/nixos/services/hindsight";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/hindsight/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/hindsight/docker-compose.yml down";
      };

      wantedBy = [ "multi-user.target" ];
      wants = [
        "pihole.service"
        "dns-ready.target"
        "network-online.target"
        "tei.service"
      ];
      after = [
        "pihole.service"
        "dns-ready.target"
        "network-online.target"
        "tei.service"
      ];
    };
  };
}