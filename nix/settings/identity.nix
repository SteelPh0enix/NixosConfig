{
  userName = "steelph0enix";
  # Rootless Docker sockets live under /run/user/<uid>; the llama units need the number.
  userUid = 1000;
  hostId = "steelph0enix-pc";

  # Working checkout, not `self`: the flake is a local git input, so `self` is the committed store
  # copy rather than the dirty worktree `nh` should build.
  repoPath = "/home/steelph0enix/nixos-config";

  # Kept literal in flake.nix too: flake input URLs cannot be interpolated.
  llamaCppPath = "/home/steelph0enix/llama.cpp";
}
