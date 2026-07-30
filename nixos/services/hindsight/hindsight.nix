{ pkgs, ... }:

{
  systemd.services = {
    "hindsight" = {
      description = "Hindsight memory service";
      enable = true;
      enableStrictShellChecks = true;

      serviceConfig = {
        WorkingDirectory = "/etc/nixos/nixos/services/hindsight";
        # `After=tei.service` only waits for Compose to be launched, not for
        # both models to load.  Wait for both endpoints before starting the
        # retrying Hindsight container.
        ExecStartPre = "${pkgs.writeScriptBin "wait-for-tei" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail
          urls="http://localhost:51540/health http://localhost:51541/health"
          for url in $urls; do
            for attempt in $(seq 1 300); do
              # Capture curl exit code BEFORE any branching
              ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 3 "$url" >/dev/null 2>&1
              exit_code=$?
              if [ $exit_code -eq 0 ]; then
                echo "TEI endpoint $url is ready"
                break
              fi
              # 52 = empty reply from server, 56 = connection reset by peer
              # Both mean TEI is still loading the model; retry.
              if [ $exit_code -eq 52 ] || [ $exit_code -eq 56 ]; then
                echo "TEI endpoint $url not ready yet (curl exit $exit_code), waiting... (attempt $attempt/300)"
                sleep 1
                continue
              fi
              # Any other non-zero exit code is a hard failure
              echo "TEI endpoint $url failed with curl exit code $exit_code"
              exit 1
            done
            [ $attempt -eq 300 ] && echo "Timed out waiting for TEI endpoint: $url" >&2 && exit 1
          done
          exit 0
        ''}/bin/wait-for-tei";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/hindsight/docker-compose.yml up --build --remove-orphans --yes";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/nixos/services/hindsight/docker-compose.yml down";
      };

      wantedBy = [ "multi-user.target" ];
      wants = [
        "pihole.service"
        "dns-ready.target"
        "network-online.target"
        "tei.service"
      ];
      after = [
        "pihole.service"
        "dns-ready.target"
        "network-online.target"
        "tei.service"
      ];
    };
  };
}