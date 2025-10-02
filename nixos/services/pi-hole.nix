{ lib, pkgs, ... }:

{
  systemd.services = {
    "pihole" = {
      description = "PiHole service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/pi-hole.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/pi-hole.yml down";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
