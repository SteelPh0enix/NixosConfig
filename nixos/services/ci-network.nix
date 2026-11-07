# The bridge CI jobs run on. It is created explicitly instead of leaving jobs on
# docker0 so that the host interface has a stable name the firewall can address,
# nothing is masqueraded outbound, and both directions are closed by default:
# forwarded traffic (the internet, the LAN) is dropped, and inbound traffic is
# accepted only for the gateway listeners and Forgejo's API.
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

    # The runner reads /run/docker.sock (its unit is in the `docker` group); a user
    # shell's DOCKER_HOST points at that user's rootless daemon instead.
    unset DOCKER_HOST

    docker network inspect ${settings.ciNetwork} >/dev/null 2>&1 || \
      docker network create \
        --driver bridge \
        --subnet ${settings.ciSubnet} \
        --gateway ${settings.ciGateway} \
        --opt com.docker.network.bridge.name=${settings.ciBridge} \
        --opt com.docker.network.bridge.enable_ip_masquerade=false \
        --opt com.docker.network.bridge.enable_icc=false \
        ${settings.ciNetwork}

    # A job that could forward would reach the internet and the LAN around the
    # gateway. Services on this host are reached through INPUT, so this costs
    # nothing the allowlist in nixos-fw does not allow anyway.
    iptables -w -C DOCKER-USER -i ${settings.ciBridge} -j DROP 2>/dev/null || \
      iptables -w -I DOCKER-USER 1 -i ${settings.ciBridge} -j DROP
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

  # The daemon builds DOCKER-USER from nothing every time it starts, so a docker
  # restart would leave the bridge open until the next boot. The script above is
  # idempotent, so the daemon runs it again as soon as it is up.
  systemd.services.docker.serviceConfig.ExecStartPost = [ ensureBridge ];

  # nixos-fw matches no interface on the global allowedTCPPorts and accepts
  # ESTABLISHED,RELATED before them, so an interface-scoped allowedTCPPorts entry
  # could only ever widen the firewall. Both rules below go in ahead of those: the
  # listeners named first, then everything else from the bridge. IPv4 only - the
  # bridge has no IPv6 (container.enable_ipv6 stays false).
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
