# Host/user identity and the checkouts the flake inputs point at.
{
  userName = "steelph0enix";
  hostId = "RX-78-FPC";

  # Working checkout, not `self`: the flake is a local git input, so `self` is the
  # committed store copy rather than the dirty worktree `nh` should build.
  repoPath = "/home/steelph0enix/nixos-config";

  # Kept literal in flake.nix too, since flake input URLs cannot be interpolated.
  llamaCppPath = "/home/steelph0enix/llama.cpp";
}
