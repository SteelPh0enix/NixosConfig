{ settings, ... }:
{
  networking.networkmanager.enable = true;
  networking.hostName = settings.hostId;

  # pi and omp route by these names, and their extensions probe a server in under two seconds -
  # too short for a round trip to AdGuard. Plain glibc resolution is enough now: framework-pc's
  # AdGuard runs `ratelimit = 200` per client subnet, so it no longer drops replies under bursts.
  networking.hosts = {
    "${settings.frameworkIp}" = [
      settings.frameworkHost
      settings.searchDomain
    ];
    "${settings.pcIp}" = [ settings.pcHost ];
  };

  networking.firewall = {
    enable = true;
    # The router and its log viewer (nixos/services/llama-server-vulkan, llama-logs), used by the
    # other box. Neither carries an API key: the LAN is the ACL.
    allowedTCPPorts = [
      settings.llmPort
      settings.llamaLogsPort
    ];
    trustedInterfaces = [ "docker0" ];
    checkReversePath = "strict";
    extraCommands = "iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns";
  };
}
