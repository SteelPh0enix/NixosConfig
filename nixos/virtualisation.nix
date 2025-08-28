{ ... }:
{
  virtualisation = {
    appvm.enable = true;
    containerd.enable = true;
    containers.enable = true;
    cri-o.enable = true;
    docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
      autoPrune.dates = "daily";
      docker.rootless.enable = true;
      docker.rootless.setSocketVariable = true;
      libvirtd.enable = true;
    };
  };

  };
}
