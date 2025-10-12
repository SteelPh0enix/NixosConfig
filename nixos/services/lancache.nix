{ pkgs, ... }:

{
  systemd.services = {
    "lancache" = {
      description = "LanCache service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/mnt/SSD/lancache";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /mnt/SSD/lancache/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /mnt/SSD/lancache/docker-compose.yml down";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
