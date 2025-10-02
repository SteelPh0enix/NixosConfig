{ lib, pkgs, ... }:

{
  systemd.services = {
    "open-webui" = {
      description = "Open-WebUI service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartMaxDelaySec = lib.mkOverride 90 "1m";
        RestartSec = lib.mkOverride 90 "100ms";
        RestartSteps = lib.mkOverride 90 9;
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/open-webui.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/open-webui.yml down";
      };
    };
  };
}
