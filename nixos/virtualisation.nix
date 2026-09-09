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
    virtualbox.host = {
      enable = true;
      enableKvm = false;
      enableExtensionPack = true;
      enableHardening = true;
      addNetworkInterface = false;
    };
    oci-containers.backend = "docker";
  };

  networking.firewall.trustedInterfaces = [ "docker0" ];
}
