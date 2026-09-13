{
  virtualisation = {
    containerd.enable = true;
    containers.enable = true;
    cri-o.enable = true;
    libvirtd.enable = true;
    docker = {
      enable = true;
      enableOnBoot = true;
      rootless.enable = true;
      rootless.setSocketVariable = true;
      autoPrune.enable = true;
    };
    oci-containers.backend = "docker";
  };

  networking.firewall.trustedInterfaces = [ "docker0" ];
}
