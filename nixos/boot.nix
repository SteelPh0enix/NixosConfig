{
  inputs,
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
  # Taken from `nixpkgs-stable` (see flake.nix); virtualbox-host's modules follow this set.
  boot.kernelPackages =
    inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.linuxPackages_zen;

  # Unstable's device-tree module defaults to `kernel.buildDTBs`, which the stable kernel package
  # does not carry; there is no DTB to build on x86 anyway.
  hardware.deviceTree.enable = false;

  # Same for `kernel.target`: the release kernel predates that attribute, and its default is what
  # the bootloader needs to copy out of the kernel output.
  system.boot.loader.kernelFile = "bzImage";

  boot.tmp.useTmpfs = true;
}
