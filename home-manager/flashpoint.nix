# The launcher app only (no game data); built by nix/overlays/flashpoint.nix.
# https://flashpointarchive.org/datahub/Linux_Support
{ pkgs, ... }:
{
  # The launcher takes the Flashpoint root from its working directory (~/.local/share/flashpoint,
  # pinned by the wrapper). The support applications it launches content with (FPSoftware: routers,
  # projectors, the Wine runtime) are not part of the launcher archive and have to be put there from
  # the full Linux build. Wine itself comes from the container and uses the host's ~/.wine prefix.
  home.packages = [ pkgs.flashpoint ];

  xdg.desktopEntries.flashpoint = {
    name = "Flashpoint Launcher";
    comment = "Browse and launch games and animations from the Flashpoint Archive";
    categories = [ "Game" ];
    exec = "flashpoint %U";
    mimeType = [ "x-scheme-handler/flashpoint" ]; # flashpoint://run/<game-id> shortcuts
  };
}
