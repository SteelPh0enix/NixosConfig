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

  # Zen: mainline plus the desktop patch set, and Hydra builds it for cache.nixos.org. This box is
  # a desktop, so it takes the desktop tweaks over XanMod's server-leaning config.
  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.tmp.useTmpfs = true;
}
