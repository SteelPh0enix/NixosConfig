{
  pkgs,
  settings,
  ...
}:

let
  # Plain runtime path into the working checkout, not a store path.
  composeDir = "${settings.repoPath}/nixos/services/llm-router-rocm";
in
{
  systemd.services = {
    "llm-router-rocm" = {
      description = "LLM Router ROCm (HIP) service - community kyuzo Strix Halo image on port 51536";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = composeDir;
        ExecStart = "${pkgs.docker}/bin/docker compose -f ${composeDir}/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f ${composeDir}/docker-compose.yml down";
        Restart = "on-failure";
        RestartSec = 10;
      };

      wantedBy = [ "multi-user.target" ];
      wants = [
        "pihole.service"
        "dns-ready.target"
        "network-online.target"
      ];
      after = [
        "pihole.service"
        "dns-ready.target"
        "network-online.target"
      ];
    };
  };
}
