{ config, pkgs, ... }:
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "text/html" = "firefox.desktop";
      "inode/directory" = "thunar.desktop";
      "application/pdf" = "org.gnome.Evince.desktop";
      "text/plain" = "nvim.desktop";
      # Wildcard keys (`image/*`) are ignored for DEFAULTS by both xdg-mime and glib, and the
      # fallback is then the first claimant in the profile's mimeinfo.cache. Spell out the types.
      "image/png" = "imv.desktop";
      "image/jpeg" = "imv.desktop";
      "image/gif" = "imv.desktop";
      "image/webp" = "imv.desktop";
      "image/bmp" = "imv.desktop";
      "image/svg+xml" = "imv.desktop";
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "audio/mpeg" = "io.github.quodlibet.QuodLibet.desktop";
      "audio/flac" = "io.github.quodlibet.QuodLibet.desktop";
      "audio/ogg" = "io.github.quodlibet.QuodLibet.desktop";
      "application/zip" = "org.gnome.FileRoller.desktop";
      "application/x-7z-compressed" = "org.gnome.FileRoller.desktop";
      "application/x-tar" = "org.gnome.FileRoller.desktop";
      "application/gzip" = "org.gnome.FileRoller.desktop";
      "x-scheme-handler/flashpoint" = "flashpoint.desktop";
    };
  };

  # Without a Terminal Execution spec, Terminal=true desktop files quietly do nothing.
  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "org.wezfurlong.wezterm.desktop" ];
  };

  # Thunar runs `exo-open --launch TerminalEmulator`, and libexo resolves this value as a bare
  # executable on $PATH with no arguments. wezterm without `--cwd` starts in $HOME even though
  # exo-open spawns it inside the selected folder, hence the wrapper.
  home.packages = [
    (pkgs.writeShellScriptBin "wezterm-terminal" ''
      exec ${config.programs.wezterm.package}/bin/wezterm start --cwd "$(pwd)" "$@"
    '')
  ];

  xdg.configFile."xfce4/helpers.rc".text = ''
    [Default]
    TerminalEmulator=wezterm-terminal
  '';

  # Real XDG directories for Noctalia's screenshots and wallpapers; user-dirs.conf is written with
  # enabled = false, so xdg-user-dirs-update never rewrites them.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = false;
  };
}
