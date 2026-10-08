# Journal tail of llama-server-vulkan over HTTP (server.py + index.html next to this file).
# Served straight from the working checkout, not a store path: edit the viewer and restart the
# unit, no rebuild.
{
  pkgs,
  settings,
  ...
}:
let
  logsServer = "${settings.repoPath}/nixos/services/llama-vulkan-logs/server.py";
in
{
  users.groups.llama-logs = { };
  users.users.llama-logs = {
    group = "llama-logs";
    isSystemUser = true;
    # The only privilege: reading the persistent journal.
    extraGroups = [ "systemd-journal" ];
  };

  systemd.services.llama-vulkan-logs = {
    description = "Web interface for llama-server-vulkan logs (${toString settings.llamaLogsPort})";
    wantedBy = [ "multi-user.target" ];
    after = [
      "llama-server-vulkan.service"
      "network-online.target"
    ];
    wants = [
      "llama-server-vulkan.service"
      "network-online.target"
    ];

    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${logsServer} --service llama-server-vulkan --port ${toString settings.llamaLogsPort}";
      User = "llama-logs";
      Group = "llama-logs";
      Restart = "on-failure";
      RestartSec = 5;

      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      PrivateIPC = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      LockPersonality = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectProc = "invisible";
      SystemCallArchitectures = "native";
      UMask = "0077";
    };
  };
}
