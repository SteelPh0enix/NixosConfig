{
  pkgs,
  settings,
  ...
}:

let
  # Plain runtime path into the working checkout, not a store path: editing the compose file
  # and restarting the unit is enough, no rebuild needed.
  composeDir = "${settings.repoPath}/nixos/services/pihole";
in
{
  systemd.services = {
    "pihole" = {
      description = "PiHole service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = composeDir;
        ExecStart = "${pkgs.docker}/bin/docker compose -f ${composeDir}/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f ${composeDir}/docker-compose.yml down";
      };

      wantedBy = [
        "multi-user.target"
        "dns-ready.target"
      ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      before = [ "dns-ready.target" ];
    };
  };
}
