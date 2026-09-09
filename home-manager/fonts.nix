{
  fonts = {
    fontconfig = {
      defaultFonts = {
        serif = [ "Berkeley Mono" ];
        emoji = [ "Noto Color Emoji" ];
        sansSerif = [ "Berkeley Mono" ];
        # Symbols Nerd Font Mono (nerd-fonts.symbols-only, nixos/fonts.nix) supplies the
        # private-use glyphs; the font package itself comes from ./nonfree-fonts.nix.
        monospace = [
          "Berkeley Mono"
          "Symbols Nerd Font Mono"
        ];
      };
      enable = true;
    };
  };
}
