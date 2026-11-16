# Journal tail of the router unit (settings.llamaRouterService) over HTTP. server.py and index.html
# are copied into the store, since the checkout is 0700 and the llama-logs user cannot read it.
{
  pkgs,
  settings,
  ...
}:
let
  # Flake path literals reach the store under hashed names (`…-server.py`), so the copies have to
  # name the targets: server.py reads index.html from its own directory.
  viewer = pkgs.runCommand "llama-logs-viewer" { } ''
    mkdir -p $out
    cp ${./server.py} $out/server.py
    cp ${./index.html} $out/index.html
  '';
in
{
  users.groups.llama-logs = { };
  users.users.llama-logs = {
    group = "llama-logs";
    isSystemUser = true;
    # The only privilege: reading the persistent journal.
    extraGroups = [ "systemd-journal" ];
  };

  systemd.services.llama-logs = {
    description = "Web interface for ${settings.llamaRouterService} logs (${toString settings.llamaLogsPort})";
    wantedBy = [ "multi-user.target" ];
    after = [
      "${settings.llamaRouterService}.service"
      "network-online.target"
    ];
    wants = [
      "${settings.llamaRouterService}.service"
      "network-online.target"
    ];

    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${viewer}/server.py --service ${settings.llamaRouterService} --port ${toString settings.llamaLogsPort}";
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
