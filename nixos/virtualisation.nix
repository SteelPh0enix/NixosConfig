{
  virtualisation = {
    containerd.enable = true;
    containers.enable = true;
    cri-o.enable = true;
    libvirtd.enable = true;
    docker = {
      enable = true;
      enableOnBoot = true;
    };
    virtualbox.guest = {
      enable = true;
      seamless = true;
      dragAndDrop = true;
      clipboard = true;
    };
  };

  networking.firewall.trustedInterfaces = [ "docker0" ];
}
