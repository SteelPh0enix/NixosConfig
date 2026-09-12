{ pkgs, config, ... }:
{
  # GTK and cursor theme for the session: nothing else writes these per user.
  gtk = {
    enable = true;
    theme.name = "Adwaita:dark"; # colon = dark variant of GTK's built-in Adwaita
    gtk4.theme = config.gtk.theme; # stateVersion < 26.05 would otherwise only warn about it
    iconTheme.name = "Adwaita";
    font = {
      name = "Berkeley Mono"; # explicit is deterministic; fontconfig does the fallback
      size = 11;
    };
  };

  # libadwaita/GTK4 apps ignore gtk-theme-name and read this instead.
  dconf = {
    enable = true;
    settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  };

  # gtk3 platform theme: Qt derives its palette from the GTK theme above, so one theme drives both.
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };

  home.pointerCursor = {
    enable = true; # gtk.enable alone is not enough
    gtk.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
  };
}
