# Journal tail of every LLM engine over HTTP. server.py + index.html live next to this file
# and are packaged into the Nix store so the unprivileged llama-logs user can reach them
# (the working checkout is mode 0700 and not world-traversable).
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
    description = "Web interface for the LLM engines' logs (${toString settings.llamaLogsPort})";
    # Boots with the boot engine and follows all three, so it is useful whichever one is up.
    wantedBy = [ "multi-user.target" ];
    after = [
      "gufo.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${viewer}/server.py --service llama-server-rocm --service llama-server-vulkan --service gufo --port ${toString settings.llamaLogsPort}";
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
