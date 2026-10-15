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

  # XanMod: mainline plus its performance config, and Hydra builds it for cache.nixos.org. This
  # box is a server (LLM inference, game servers), so throughput over desktop tweaks.
  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;

  boot.tmp.useTmpfs = true;
}
