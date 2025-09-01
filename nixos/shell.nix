{
  environment.shellAliases = {
    ls = "eza";
    l = "eza -lh";
    la = "eza -alh";
    lg = "lazygit";
    e = "$EDITOR";
    eh = "$EDITOR .";
    pkgu = "cd ~/nixos-config && git checkout work-vm && git pull && nix flake update && sudo nixos-rebuild switch --flake .#steelph0enix-work-vm --upgrade-all";
    pkgc = "sudo nix-store --gc && sudo nix-store --optimise && sudo nix-collect-garbage -d && nix-collect-garbage -d";
    rbt = "sudo systemctl reboot";
    cfge = "code ~/nixos-config";
    docker-here = "docker run --rm -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)";
    docker-here-shell = "docker run --rm -it -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)";
  };

  environment.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
    TERMINAL = "wezterm";
  };

  programs.fish.shellInit = builtins.readFile ./init.fish;
  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;
}
