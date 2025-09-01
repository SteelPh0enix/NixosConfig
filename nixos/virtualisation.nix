{
  virtualisation = {
    containerd.enable = true;
    containers.enable = true;
    cri-o.enable = true;
    libvirtd.enable = true;
    docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
      autoPrune.dates = "daily";
      rootless.enable = true;
      rootless.setSocketVariable = true;
    };
    virtualbox.host = {
      enable = true;
      enableKvm = false;
      enableExtensionPack = true;
      enableHardening = true;
      addNetworkInterface = false;
    };
  };
}
