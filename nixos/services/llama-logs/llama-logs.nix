# Journal tail of every LLM engine over HTTP; the files are packaged so the llama-logs user can
# read them.
{
  pkgs,
  settings,
  ...
}:
let
  # Hashed store names, so copy by name: server.py reads index.html from its own directory.
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
    extraGroups = [ "systemd-journal" ];
  };

  systemd.services.llama-logs = {
    description = "Web interface for the LLM engines' logs (${toString settings.llamaLogsPort})";
    # Boots with the boot engine and follows all three engines plus gufo-auth.
    wantedBy = [ "multi-user.target" ];
    after = [
      "gufo.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${viewer}/server.py --service llama-server-rocm --service llama-server-vulkan --service gufo --service gufo-auth --port ${toString settings.llamaLogsPort}";
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
