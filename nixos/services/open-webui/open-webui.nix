{ pkgs, ... }:

{
  systemd.services = {
    "open-webui" = {
      description = "Open-WebUI service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/etc/nixos/nixos/services/open-webui";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/open-webui/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/open-webui/docker-compose.yml down";
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
