{
  environment.shellAliases = {
    ls = "eza --icons=always -gM --git";
    l = "ls -lh";
    la = "ls -alh";
    lg = "lazygit";
    e = "$EDITOR";
    eh = "$EDITOR .";
    os-rebuild = "cd ~/nixos-config && sudo nixos-rebuild switch --flake .#steelph0enix-work-vm --upgrade-all --print-build-logs --show-trace --refresh";
    os-update = "cd ~/nixos-config && nix flake update && os-rebuild && git add flake.lock && git commit -m 'os update'";
    os-clean = "sudo nix-store --gc && sudo nix-store --optimise && sudo nix-collect-garbage -d && nix-collect-garbage -d";
    rbt = "sudo systemctl reboot";
    cfge = "code ~/nixos-config";
    docker-here = "docker run --rm -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)";
    docker-here-shell = "docker run --rm -it -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)";
  };

  environment.sessionVariables = {
    BROWSER = "firefox";
    TERMINAL = "wezterm";
  };

  programs.fish.shellInit = builtins.readFile ./init.fish;
  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;
}
