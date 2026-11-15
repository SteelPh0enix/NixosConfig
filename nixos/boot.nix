{
  pkgs,
  ...
}:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 5;
    consoleMode = "max";
    editor = false;
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 5;

  # XanMod: mainline plus its performance config, cached by Hydra.
  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;

  # /tmp on the root filesystem: the LLM pool is the scarce resource.
  boot.tmp.useTmpfs = false;
  boot.tmp.cleanOnBoot = true;
}
