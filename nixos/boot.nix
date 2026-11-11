{
  pkgs,
  lib,
  ...
}:
let
  # 7.3.3 has this tooling header upstream already, so nixpkgs' patch applies in reverse and
  # kills the build. nixpkgs drops it in e99a4dcc; the pinned nixos-unstable predates that commit.
  dropAppliedPatch = lib.filter (p: p.name != "tools-add-128-bit-integer-types-for-aarch64");
in
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
  boot.kernelPackages = pkgs.linuxPackagesFor (
    pkgs.linux_xanmod_latest.override {
      kernelPatches = dropAppliedPatch pkgs.linux_xanmod_latest.kernelPatches;
    }
  );

  boot.tmp.useTmpfs = true;
}
