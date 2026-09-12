{ pkgs, config, ... }:
{
  # GTK and cursor theme for the session: nothing else writes these per user.
  gtk = {
    enable = true;
    # GTK's built-in Adwaita, no ":dark" suffix: GTK 3 only splits that off $GTK_THEME, so in
    # settings.ini it names a theme called "Adwaita:dark" - missing, hence the unthemed light UI.
    theme.name = "Adwaita";
    colorScheme = "dark"; # -> gtk-application-prefer-dark-theme (gtk3) + prefer-dark (dconf/gtk4)
    gtk4.theme = config.gtk.theme; # stateVersion < 26.05 would otherwise only warn about it
    iconTheme.name = "Adwaita";
    font = {
      name = "Berkeley Mono"; # explicit is deterministic; fontconfig does the fallback
      size = 11;
    };
  };

  # gtk.colorScheme writes the GNOME color-scheme (what libadwaita/GTK4 apps read) into dconf,
  # but only if dconf is enabled.
  dconf.enable = true;

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
