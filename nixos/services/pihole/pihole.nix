{ pkgs, ... }:

{
  systemd.services = {
    "pihole" = {
      description = "PiHole service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/etc/nixos/nixos/services/pihole";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/pihole/pihole.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/pihole/pihole.yml down";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
