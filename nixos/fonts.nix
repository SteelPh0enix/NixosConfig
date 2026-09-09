{ pkgs, ... }:
{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      material-design-icons

      font-awesome

      nerd-fonts.symbols-only
      nerd-fonts.monaspace
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
    ];
  };
}
