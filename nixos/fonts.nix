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

    fontconfig = {
      defaultFonts = {
        serif = [ "Noto Serif" ];
        emoji = [ "Noto Color Emoji" ];
        sansSerif = [ "Noto Sans" ];
        monospace = [ "Monaspace Krypton NF" ];
      };
    };
  };

}
