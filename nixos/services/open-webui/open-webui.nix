{ pkgs, ... }:

{
  systemd.services = {
    "open-webui" = {
      description = "Open-WebUI service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/etc/nixos/nixos/services/open-webui";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/open-webui/open-webui.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/open-webui/open-webui.yml down";
      };

      wantedBy = [ "multi-user.target" ];
      after = [ "pihole.service" ];
    };
  };
}
