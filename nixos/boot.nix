{
  pkgs,
  ...
}:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 3;
    consoleMode = "max";
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 3;

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen
;
}
