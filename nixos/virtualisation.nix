{
  # Rootless for local use; the system daemon runs CI jobs.
  virtualisation.docker = {
    enable = true;
    rootless.enable = true;
    rootless.setSocketVariable = true;
    autoPrune.enable = true;
  };

  networking.firewall.trustedInterfaces = [ "docker0" ];
}
