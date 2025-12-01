{ pkgs, ...}:
{
  environment.shellAliases = {
    ls = "eza --icons=always -gM --git";
    l = "ls -lh";
    la = "ls -alh";
    lg = "lazygit";
    e = "$EDITOR";
    eh = "$EDITOR .";
    cpr = "cp -r";
    rbt = "sudo systemctl reboot";
    cfge = "$EDITOR ~/nixos-config";
    cfgevis = "$EDITOR ~/nixos-config";
    docker-here = "docker run --rm -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)";
    docket-here-dotnet = "docker run --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --rm -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g) -e DOTNET_CLI_HOME=/tmp";
    docker-here-shell = "docker run --rm -it -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)";
    rcp = "rsync --archive --recursive --mkpath --verbose --progress --human-readable";
    rcpc = "rsync --archive --recursive --mkpath --compress --verbose --progress --human-readable";
  };

  environment.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
    TERMINAL = "wezterm";
    LD_LIBRARY_PATH = "${pkgs.ncurses5}/lib";
  };

  programs.fish.shellInit = builtins.readFile ./init.fish;
  programs.nix-index.enable = true;
  programs.nix-index.enableFishIntegration = true;
  programs.nix-index-database.comma.enable = true;
}
