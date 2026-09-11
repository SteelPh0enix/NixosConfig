{ pkgs, ... }:
{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts # keeps the generic families resolvable for non-user processes
      material-design-icons

      font-awesome

      nerd-fonts.symbols-only
      nerd-fonts.monaspace
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
    ];

    # Defaults for processes that do not run as this user. Berkeley Mono is deliberately absent:
    # its licence is per user, and the per-user config keeps the session on it regardless.
    fontconfig.defaultFonts = {
      sansSerif = [ "Noto Sans" ];
      serif = [ "Noto Serif" ];
      monospace = [ "Noto Sans Mono" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  # Sets GDK_PIXBUF_MODULE_FILE; without it the SVG icon themes GTK/Thunar use render blank.
  programs.gdk-pixbuf.modulePackages = [ pkgs.librsvg ];
}
