{ pkgs, ... }:
{
  systemd.services.minecraft-server = {
    description = "Minecraft Server (OC 1.21.11)";
    after = [
      "network.target"
      "docker.service"
    ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "steelph0enix";
      Group = "users";
      WorkingDirectory = "/home/steelph0enix/Minecraft/OC_1_21_11";
      Restart = "always";
      RestartSec = "10";
      TimeoutStartSec = "10min";
    };

    preStart = ''
      ${pkgs.docker-compose}/bin/docker-compose pull
    '';

    script = ''
      ${pkgs.docker-compose}/bin/docker-compose up
    '';

    preStop = ''
      ${pkgs.docker-compose}/bin/docker-compose down
    '';
  };

  networking.firewall.allowedTCPPorts = [ 26969 ];
}
