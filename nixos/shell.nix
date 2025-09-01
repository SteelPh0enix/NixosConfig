{
  environment.shellAliases = {
    ls = "eza";
    l = "eza -lh";
    la = "eza -alh";
    lg = "lazygit";
    e = "$EDITOR";
    eh = "$EDITOR .";
    pkgu = "cd ~/nixos-config && nix flake update && sudo nixos-rebuild switch --flake .#steelph0enix-work-vm --upgrade-all";
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
}
