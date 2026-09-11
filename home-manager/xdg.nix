{ ... }:
{
  # xdg.enable is already on in shell.nix; xdg.mime (shared-mime-info + update-desktop-database over
  # the profile) defaults to true on Linux, so only the associations and dirs below are needed.
  xdg.mimeApps = {
    enable = true; # writes ~/.config/mimeapps.list
    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "text/html" = "firefox.desktop";
      "inode/directory" = "thunar.desktop";
      "application/pdf" = "org.gnome.Evince.desktop";
      "text/plain" = "nvim.desktop"; # Terminal=true, so terminal-exec opens it in wezterm
      "image/*" = "imv.desktop";
      "video/*" = [
        "mpv.desktop"
        "vlc.desktop"
      ];
      "audio/*" = [
        "vlc.desktop"
        "io.github.quodlibet.QuodLibet.desktop"
      ];
      # thunar-archive-plugin drives whatever handles these
      "application/zip" = "org.gnome.FileRoller.desktop";
      "application/x-7z-compressed" = "org.gnome.FileRoller.desktop";
      "application/x-tar" = "org.gnome.FileRoller.desktop";
      "application/gzip" = "org.gnome.FileRoller.desktop";
      # x-scheme-handler/mailto deliberately unset: no mail client installed ("Open with…" still works).
    };
  };

  # Default Terminal Execution spec: what "Open Terminal here" and any Terminal=true desktop file
  # launches. Without it those quietly do nothing.
  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "org.wezfurlong.wezterm.desktop" ];
  };

  # Gives Noctalia real XDG directories to use for screenshots/wallpapers. Also writes
  # user-dirs.conf (enabled = false) so xdg-user-dirs-update never rewrites this at runtime.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = false; # the future default; apps read ~/.config/user-dirs.dirs
  };
}
