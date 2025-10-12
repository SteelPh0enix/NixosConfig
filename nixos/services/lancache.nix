{ pkgs, ... }:
{
  systemd.services = {
    "lancache" = {
      description = "LanCache service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/mnt/SSD/lancache";
        ExecStart = "${pkgs.fish}/bin/fish /mnt/SSD/lancache/start-lancache.fish";
        ExecStop = "${pkgs.fish}/bin/fish /mnt/SSD/lancache/stop-lancache.fish";
      };

      path = [
        pkgs.docker
        pkgs.iproute2
        pkgs.fish
      ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
  };
}
