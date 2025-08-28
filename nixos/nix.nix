{ ... }:
{
  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 3d";
  };

  nix.settings.auto-optimise-store = true;
  nix.channel.enable = false;
}
