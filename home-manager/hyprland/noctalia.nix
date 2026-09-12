{ pkgs, ... }:
{
  # Bar, launcher, control centre, tray, notifications, clipboard history, wallpaper, screenshots,
  # night light, window switcher, power-profile widget, session lock + idle.
  # See https://docs.noctalia.dev/v5
  programs.noctalia = {
    enable = true;
    package = pkgs.noctalia; # v5; NOT pkgs.noctalia-shell (frozen v4)
    systemd.enable = true; # PartOf/WantedBy = wayland.systemd.target; enable it HERE only
    checkConfig = true; # builds `noctalia config validate` on the generated file

    settings = {
      # Values changed in the Settings GUI (SUPER+comma) land in ~/.local/state/noctalia/settings.toml,
      # which merges LAST and wins over this file. Anything declared here must therefore also be
      # deleted from that state file; Noctalia prunes an override once it matches the declarative value.
      # `community` fetches the palette from api.noctalia.dev at runtime (cached in the state dir) -
      # the choice is declarative, the palette file is not.
      theme = {
        mode = "dark";
        source = "community";
        community_palette = "Cyberpunk";
        wallpaper_scheme = "m3-content"; # only read when source = "wallpaper"
        templates.builtin_ids = [
          "btop"
          "gtk3"
          "gtk4"
          "hyprland"
          "qt"
          "wezterm"
        ]; # opt-in; list ids with `noctalia theme --list-templates`
      };

      shell = {
        font_family = "Berkeley Mono";
        setup_wizard_enabled = false; # declarative box: no first-run wizard
        corner_radius_scale = 0.7;
        screen_time_enabled = true; # per-app usage tracking, shown in the control centre
        launcher.show_app_actions = true; # .desktop actions (New Window, ...) in the launcher menu
        screenshot = {
          directory = "~/Pictures/Screenshots"; # `~` is expanded; "" would mean XDG Pictures
          copy_to_clipboard = true;
        };
        # Declaring the list REPLACES the built-in five actions (lock, logout, lock_and_suspend,
        # reboot, shutdown). `logout` defaults to the compositor-native exit, which must not happen
        # under uwsm, so only its handler is replaced. `lock` stays out of the panel: SUPER+L
        # covers it (hyprland/bindings.lua). A row `command` always runs via /bin/sh -c instead of
        # the built-in handler; [shell.session.power] would override suspend/reboot/shutdown
        # globally.
        session.actions = [
          {
            action = "logout";
            command = "uwsm stop";
          }
          { action = "suspend"; }
          { action = "reboot"; }
          {
            action = "shutdown";
            variant = "destructive";
            countdown_seconds = 5;
          }
        ];
      };

      notification.enable_daemon = true; # Noctalia owns org.freedesktop.Notifications

      audio.enable_sounds = true; # master toggle for UI feedback sounds

      # Only the switch is declarative: calendar.account.* carries the Google account id and stays
      # in ~/.local/state/noctalia/settings.toml.
      calendar.enabled = true;

      dock = {
        enabled = true;
        reserve_space = false; # overlay the dock instead of reserving a gap
        show_dots = true; # running-app indicator dots
        smart_auto_hide = true; # visible while the workspace is empty, hidden once it has windows
      };

      # DisplayPort panels expose nothing under /sys/class/backlight, so the brightness keys and the
      # bar widget need DDC/CI: Noctalia shells out to `ddcutil` (systemPackages) over /dev/i2c-*
      # (hardware.i2c). Without it: `noctalia msg brightness-up` -> "brightness control unavailable".
      brightness.enable_ddcutil = true;

      # Session lock: ext-session-lock-v1, unlock through PAM service "login" (hardcoded, so it uses
      # the service NixOS already ships; passwords go through the setuid unix_chkpwd helper,
      # fingerprint would need fprintd). There is no non-PAM fallback, so test SUPER+L on the very
      # first session. It also holds a sleep inhibitor, so suspend locks first.
      lockscreen = {
        enabled = true;
        lock_before_suspend = true;
        fingerprint = false; # no fprintd on this host
      };

      # Idle: ext_idle_notifier_v1 with native actions (lock | screen_off | suspend |
      # lock_and_suspend | command). screen_off goes through Hyprland's own DPMS dispatch and
      # wakes the monitors back up.
      idle = {
        behavior_order = [
          "lock"
          "screen-off"
        ];
        behavior.lock = {
          action = "lock";
          enabled = true;
          timeout = 300;
        };
        behavior.screen-off = {
          action = "screen_off";
          enabled = true;
          timeout = 900;
        };
      };

      # Names in a lane are widget types; [widget.<name>] re-tunes one or adds a second copy
      # (e.g. [widget.clock-seconds] type = "clock"). The network and bluetooth widgets - plus the
      # power-profile switch in the control centre - are why no nm-applet/blueman-applet is needed.
      bar.default = {
        capsule = true; # pill background behind every widget; [widget.<name>].capsule overrides
        start = [
          "launcher"
          "workspaces"
        ];
        center = [ "clock" ];
        # upstream's default lane minus battery (this is a desktop) and the wallpaper picker
        end = [
          "media"
          "tray"
          "notifications"
          "clipboard"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "control-center"
          "session"
        ];
      };

      # No plugins are declared: "all" makes the shell git-clone the official+community sources on
      # startup and every 6 h. Valid: "all" | "official" | "none".
      plugins.auto_update = "none";
      plugins.enabled = [ "nightwatch75/file-search" ]; # plugins to load, as "author/name"
    };
  };

  # NixOS `programs.noctalia` stays disabled on purpose: it would install a second noctalia.service.
}
