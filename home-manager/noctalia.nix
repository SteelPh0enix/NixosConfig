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
          "niri"
          "qt"
          "wezterm"
        ]; # opt-in; list ids with `noctalia theme --list-templates`
        # No lazygit: its hook merges the palette into ~/.config/lazygit/config.yml, which Home
        # Manager writes from programs.lazygit.settings - a store symlink the hook cannot edit.
        templates.community_ids = [
          "pi-agent"
          "discord"
          "inkscape"
          "libreoffice"
          "neovim"
          "vscode"
          "prismlauncher"
          "steam"
          "fastfetch"
          "obs"
          "fzf"
        ]; # opt-in; ids come from api.noctalia.dev/templates, cached in the state dir
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
        # reboot, shutdown). `lock` stays out of the panel: SUPER+L covers it (niri/config.kdl).
        # A row `command` always runs via /bin/sh -c instead of the built-in handler;
        # [shell.session.power] would override suspend/reboot/shutdown globally.
        session.actions = [
          {
            action = "logout";
            # Explicit rather than the built-in handler: niri asks for confirmation this way.
            command = "niri msg action quit";
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

      # pkexec and removable-media prompts need a polkit agent; Noctalia's own is the only one here.
      shell.polkit_agent = true;

      # phonto plays the animated wallpapers (home-manager/phonto.nix). Noctalia's wallpaper is a
      # zwlr-layer-shell surface on the same layer, so exactly one of the two may be enabled.
      wallpaper.enabled = false;

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
      # lock_and_suspend | command): screen_off turns the monitors off and any input wakes them.
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
          "cpu"
          "ram"
          "network_rx"
          "network_tx"
          "temp"
          "weather"
        ];
        center = [
          "clock"
          "file-search"
        ];
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
          "power_profile"
          "control-center"
          "session"
        ];
      };

      widget.media = {
        hide_when_no_media = true; # drop the widget while no MPRIS player is active
        show_progress = true;
        title_scroll = "always"; # none | always | on_hover
      };

      # A plugin widget has no built-in type name: the bar lane says "file-search", the plugin
      # declares it as "<plugin id>:<widget id>" (see plugins.enabled). checkConfig therefore logs
      # `unrecognized widget type` while building - the plugin registry is cloned into the state dir
      # at runtime and the sandbox has none of it. Same command with HOME set reports no warning, and
      # validate exits 0 on warnings, so this is noise, not a rejected key.
      widget.file-search.type = "nightwatch75/file-search:file-search";

      # Widget-editor layouts (SUPER+comma -> Desktop / Lock screen). Geometry is absolute and
      # per-output: cx/cy/box_* sit inside a placement_width x placement_height rect on a named
      # connector, so this block describes THIS monitor setup (2560x1440 on DP-1) rather than a
      # portable preference - moving the panels means redoing it in the editor, not on another host.
      # schema_version is the editor's own stamp.
      desktop_widgets = {
        grid = {
          cell_size = 16;
          major_interval = 4;
          visible = true;
        };
        schema_version = 2;
        widget = {
          # top-left clock
          desktop-widget-0000000000000001 = {
            box_height = 128.0;
            box_width = 240.0;
            cx = 176.0;
            cy = 128.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "clock";
          };
          # zero-size until the editor gives it one; calendar below the clock
          desktop-widget-0000000000000002 = {
            box_height = 0.0;
            box_width = 0.0;
            cx = 364.0;
            cy = 413.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "calendar";
          };
          desktop-widget-0000000000000003 = {
            box_height = 144.0;
            box_width = 608.0;
            cx = 368.0;
            cy = 712.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            settings = {
              bands = 32;
              show_when_idle = true;
            };
            type = "audio_visualizer";
          };
          desktop-widget-0000000000000004 = {
            box_height = 160.0;
            box_width = 256.0;
            cx = 2368.0;
            cy = 160.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            settings = {
              stat = "cpu_usage";
              stat2 = "cpu_temp";
            };
            type = "sysmon";
          };
          desktop-widget-0000000000000005 = {
            box_height = 160.0;
            box_width = 256.0;
            cx = 2112.0;
            cy = 160.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            settings = {
              stat = "gpu_usage";
              stat2 = "gpu_temp";
            };
            type = "sysmon";
          };
          desktop-widget-0000000000000006 = {
            box_height = 160.0;
            box_width = 256.0;
            cx = 2368.0;
            cy = 336.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            settings = {
              display = "graph";
              stat = "ram_pct";
              stat2 = "swap_pct";
            };
            type = "sysmon";
          };
          # the wired link, hence the hardcoded interface name
          desktop-widget-0000000000000007 = {
            box_height = 160.0;
            box_width = 256.0;
            cx = 2112.0;
            cy = 336.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            settings = {
              interface = "enp38s0";
              stat = "net_rx";
              stat2 = "net_tx";
            };
            type = "sysmon";
          };
          desktop-widget-0000000000000008 = {
            box_height = 128.0;
            box_width = 352.0;
            cx = 496.0;
            cy = 128.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "volume";
          };
          desktop-widget-0000000000000009 = {
            box_height = 112.0;
            box_width = 512.0;
            cx = 2240.0;
            cy = 480.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "weather";
          };
        };
        widget_order = [
          "desktop-widget-0000000000000001"
          "desktop-widget-0000000000000002"
          "desktop-widget-0000000000000003"
          "desktop-widget-0000000000000004"
          "desktop-widget-0000000000000005"
          "desktop-widget-0000000000000006"
          "desktop-widget-0000000000000007"
          "desktop-widget-0000000000000008"
          "desktop-widget-0000000000000009"
        ];
      };

      # A login box on every connected panel. enabled = false keeps the editor layout parked:
      # the lock screen itself is [lockscreen], driven by SUPER+L.
      lockscreen_widgets = {
        enabled = false;
        grid = {
          cell_size = 16;
          major_interval = 4;
          visible = true;
        };
        schema_version = 2;
        widget = {
          "lockscreen-login-box@DP-1" = {
            box_height = 196.0;
            box_width = 810.0;
            cx = 1280.0;
            cy = 1258.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            settings = {
              background_color = "surface_variant";
              background_opacity = 0.88;
              background_radius = 12.0;
              center_password_text = false;
              input_opacity = 1.0;
              input_radius = 6.0;
              layout = "regular";
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_media = true;
              show_session_buttons = true;
              show_unlock_hint = true;
              show_weather = true;
            };
            type = "login_box";
          };
          "lockscreen-login-box@DP-2" = {
            box_height = 196.0;
            box_width = 810.0;
            cx = 1280.0;
            cy = 1258.0;
            output = "DP-2";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            settings = {
              background_color = "surface_variant";
              background_opacity = 0.88;
              background_radius = 12.0;
              center_password_text = false;
              input_opacity = 1.0;
              input_radius = 6.0;
              layout = "regular";
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_media = true;
              show_session_buttons = true;
              show_unlock_hint = true;
              show_weather = true;
            };
            type = "login_box";
          };
        };
        widget_order = [
          "lockscreen-login-box@DP-2"
          "lockscreen-login-box@DP-1"
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
