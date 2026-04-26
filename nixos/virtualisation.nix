{
  virtualisation = {
    libvirtd.enable = true;
    docker = {
      enable = true;
      enableOnBoot = true;
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

  networking.firewall.trustedInterfaces = [ "docker0" ];
}
