{ pkgs, config, ... }:
{
  # GTK and cursor theme for the session: nothing else writes these per user.
  gtk = {
    enable = true;
    theme.name = "adwaita-dark";
    gtk4.theme = config.gtk.theme; # stateVersion < 26.05 would otherwise only warn about it
    iconTheme.name = "Adwaita";
    font = {
      name = "Berkeley Mono"; # explicit is deterministic; fontconfig does the fallback
      size = 11;
    };
  };

  home.pointerCursor = {
    enable = true; # gtk.enable alone is not enough
    gtk.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
  };
}
