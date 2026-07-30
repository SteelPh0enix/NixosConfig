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
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for url in http://localhost:51540/health http://localhost:51541/health; do for attempt in $(seq 1 180); do ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 3 \"$url\" >/dev/null && break; [ \"$attempt\" -eq 180 ] && echo \"Timed out waiting for TEI endpoint: $url\" >&2 && exit 1; sleep 1; done; done'";
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