{ pkgs, ... }:
{
  wayland.windowManager.niri = {
    enable = true;

    # The same derivation `programs.niri` puts on the system (nixos/niri.nix); home-manager needs a
    # non-null package to run `niri validate` over the generated file.
    package = pkgs.niri;
    checkConfig = true;

    # programs.niri ships niri's systemd units and their drop-ins system-wide.
    systemd.enable = false;

    # ... and the portal config (`niri-portals.conf`), so home-manager must not add a second one.
    portalPackage = null;

    # `xwaylandSatellitePackage` stays at its default: with xwayland-satellite on PATH niri starts
    # XWayland on demand. The Xwayland binary itself is switched on in nixos/desktop.nix.

    # Whole config in one plain KDL file, checked at build time by `niri validate` (checkConfig) and
    # on its own with `niri validate --config home-manager/niri/config.kdl`.
    extraConfig = builtins.readFile ./config.kdl;
  };
}
