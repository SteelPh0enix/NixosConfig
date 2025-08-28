{ pkgs, ... }:
{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      material-design-icons

      font-awesome
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      ubuntu_font_family
      liberation_ttf

      nerd-fonts.symbols-only
      nerd-fonts.monaspace
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
    ];
  };
}
