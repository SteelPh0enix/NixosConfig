# The bridge CI jobs run on: forwarded traffic is dropped, and inbound is accepted only for the
# gateway listeners and Forgejo's API. The unit does not re-run on a switch, so a running link
# survives activation with jobs in flight.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  # The only ports a job may reach: Forgejo's API (the one in ACTIONS_RUNTIME_URL),
  # the runner's cache proxy, and the two gateway listeners.
  allowedPorts = lib.concatStringsSep "," (
    map builtins.toString [
      settings.forgejoPort
      settings.ciCachePort
      settings.ciLlmPort
      settings.ciProxyPort
    ]
  );

  ensureBridge = pkgs.writeShellScript "ci-network" ''
    set -eu
    docker=${pkgs.docker}/bin/docker
    iptables=${pkgs.iptables}/bin/iptables

    # The runner reads /run/docker.sock; a user shell's DOCKER_HOST points at rootless docker.
    unset DOCKER_HOST

    $docker network inspect ${settings.ciNetwork} >/dev/null 2>&1 || \
      $docker network create \
        --driver bridge \
        --subnet ${settings.ciSubnet} \
        --gateway ${settings.ciGateway} \
        --opt com.docker.network.bridge.name=${settings.ciBridge} \
        --opt com.docker.network.bridge.enable_ip_masquerade=false \
        --opt com.docker.network.bridge.enable_icc=false \
        ${settings.ciNetwork}

    # A job that could forward would reach the internet and the LAN around the gateway.
    $iptables -w -C DOCKER-USER -i ${settings.ciBridge} -j DROP 2>/dev/null || \
      $iptables -w -I DOCKER-USER 1 -i ${settings.ciBridge} -j DROP
  '';
in
{
  systemd.services.ci-network = {
    description = "CI job bridge (${settings.ciSubnet} on ${settings.ciBridge})";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ensureBridge;
    };
  };

  # The daemon rebuilds DOCKER-USER from nothing on start, so re-run the idempotent script.
  systemd.services.docker.serviceConfig.ExecStartPost = [
    (pkgs.writeShellScript "ci-network-retry" ''
      ${ensureBridge} || echo "ci-network: ${settings.ciBridge} or its DOCKER-USER rule is missing" >&2
    '')
  ];

  # nixos-fw accepts ESTABLISHED before the port lists, so interface-scoped entries could only
  # widen the firewall; these rules go in ahead of those.
  networking.firewall.extraCommands = lib.mkAfter ''
    iptables -w -I nixos-fw 1 -i ${settings.ciBridge} -p tcp -d ${settings.ciGateway} \
      -m multiport --dports ${allowedPorts} -j nixos-fw-accept
    iptables -w -I nixos-fw 2 -i ${settings.ciBridge} -j DROP
  '';

  networking.firewall.extraStopCommands = lib.mkAfter ''
    iptables -w -D nixos-fw -i ${settings.ciBridge} -p tcp -d ${settings.ciGateway} \
      -m multiport --dports ${allowedPorts} -j nixos-fw-accept 2>/dev/null || true
    iptables -w -D nixos-fw -i ${settings.ciBridge} -j DROP 2>/dev/null || true
  '';
}
