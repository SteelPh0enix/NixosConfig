{
  programs.fish.shellAliases = {
    ls = "eza";
    l = "eza -lh";
    la = "eza -alh";
    lg = "lazygit";
    e = "$EDITOR";
    eh = "$EDITOR .";
    pkgu = "sudo nix-channel --update && sudo nixos-rebuild switch --flake .#steelph0enix-pc --upgrade-all";
    pkgc = "sudo nix-store --gc && sudo nix-store --optimise && sudo nix-collect-garbage -d && nix-collect-garbage -d";
  };

}
