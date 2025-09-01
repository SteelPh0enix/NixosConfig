{
  pkgs,
  ...
}:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 5;
    consoleMode = "max";
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 5;

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen
;
}
