{ pkgs, ... }:

{
  systemd.services = {
    "web-extract" = {
      description = "Hermes local web extraction service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/etc/nixos/nixos/services/web-extract";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/web-extract/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/web-extract/docker-compose.yml down";
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
