{
  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 1d";
  };

  nix.settings.auto-optimise-store = true;
  nix.channel.enable = false;
}
