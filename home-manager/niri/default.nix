{ pkgs, ... }:
{
  wayland.windowManager.niri = {
    enable = true;

    # home-manager needs a non-null package to run `niri validate` over the generated file.
    package = pkgs.niri;
    checkConfig = true;

    # programs.niri ships niri's systemd units and their drop-ins system-wide.
    systemd.enable = false;

    # ... and the portal config (`niri-portals.conf`), so home-manager must not add a second one.
    portalPackage = null;

    # xwayland-satellite on PATH is what starts XWayland on demand (see nixos/desktop.nix).

    # One plain KDL file, checked at build time by `niri validate` (checkConfig).
    extraConfig = builtins.readFile ./config.kdl;
  };
}
