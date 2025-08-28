{ pkgs, ... }:
{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      ubuntu_font_family
      liberation_ttf
      nerd-fonts.monaspace
      nerd-fonts.fira-code
    ];
  };
}
