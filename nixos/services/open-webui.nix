{ lib, pkgs, ... }:

{
  systemd.services = {
    "open-webui" = {
      description = "Open-WebUI service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/open-webui.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/open-webui.yml down";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
