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
      theme.mode = "dark";

      shell = {
        font_family = "Berkeley Mono"; # Pango family; fontconfig does the fallback
        setup_wizard_enabled = false; # declarative box: no first-run wizard
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
    };
  };

  # NixOS `programs.noctalia` stays disabled on purpose: it would install a second noctalia.service.
}
