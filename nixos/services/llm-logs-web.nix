{ pkgs, ... }:

{
  systemd.services = {
    "llm-logs-web" = {
      description = "Web interface for llm-router (Vulkan) logs";
      after = [ "llm-router.service" "network-online.target" ];
      wants = [ "llm-router.service" "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 /etc/nixos/nixos/services/llm-logs-server/server.py --service llm-router --port 51580";
        Restart = "on-failure";
        RestartSec = 5;
        User = "steelph0enix";
        Group = "users";
        # Allow reading journal logs
        PrivateTmp = false;
      };
      wantedBy = [ "multi-user.target" ];
    };

    "llm-logs-web-rocm" = {
      description = "Web interface for llm-router-rocm (ROCm) logs";
      after = [ "llm-router-rocm.service" "network-online.target" ];
      wants = [ "llm-router-rocm.service" "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 /etc/nixos/nixos/services/llm-logs-server/server.py --service llm-router-rocm --port 51581";
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
