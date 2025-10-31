{ pkgs, ... }:
{
  systemd.services = {
    "lancache" = {
      description = "LanCache service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/mnt/NAS2/lancache";
        ExecStart = "${pkgs.fish}/bin/fish /mnt/NAS2/lancache/start-lancache.fish";
        ExecStop = "${pkgs.fish}/bin/fish /mnt/NAS2/lancache/stop-lancache.fish";
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
