{ pkgs, ... }:

{
  systemd.services = {
    "llm-logs-web" = {
      description = "Web interface for llm-router logs";
      after = [ "llm-router.service" "network-online.target" ];
      wants = [ "llm-router.service" "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 /etc/nixos/nixos/services/llm-logs-server/server.py";
        Restart = "on-failure";
        RestartSec = 5;
        User = "steelph0enix";
        Group = "users";
        # Allow reading journal logs
        PrivateTmp = false;
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
