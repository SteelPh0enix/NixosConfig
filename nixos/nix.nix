{ settings, ... }:
{
  # Garbage collection itself lives in `programs.nh.clean` (nixos/shell.nix).
  nix.settings.auto-optimise-store = true;
  nix.channel.enable = false;

  # cache.nixos.org + its key are already the nix defaults. Reachable caches only: a substituter
  # that refuses connections makes the daemon abort inside `queryMissing` (NixOS/nix#14758),
  # which surfaces as "Nix daemon disconnected unexpectedly".
  nix.settings.substituters = [
    "https://nix-community.cachix.org"
  ];

  nix.settings.trusted-users = [ settings.userName ];

  nix.settings.trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
