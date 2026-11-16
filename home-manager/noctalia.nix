{ pkgs, ... }:
{
  # https://docs.noctalia.dev/v5
  programs.noctalia = {
    enable = true;
    package = pkgs.noctalia; # v5; NOT pkgs.noctalia-shell (frozen v4)
    systemd.enable = true;
    checkConfig = true;

    settings = {
      # Values changed in the Settings GUI land in ~/.local/state/noctalia/settings.toml, which merges
      # LAST and wins over this file; a value declared here has to be deleted there too.
      # `community` fetches the palette from api.noctalia.dev at runtime: only the choice is declarative.
      theme = {
        mode = "dark";
        source = "community";
        community_palette = "Cyberpunk";
        wallpaper_scheme = "m3-content";
        templates.builtin_ids = [
          "btop"
          "gtk3"
          "gtk4"
          "niri"
          "qt"
          "wezterm"
        ];
        # No lazygit: its palette hook cannot edit the store symlink home-manager writes.
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
        ];
      };

      shell = {
        font_family = "Berkeley Mono";
        setup_wizard_enabled = false;
        corner_radius_scale = 0.7;
        screen_time_enabled = true;
        launcher.show_app_actions = true;
        screenshot = {
          directory = "~/Pictures/Screenshots";
          copy_to_clipboard = true;
        };
        # Declaring the list REPLACES the built-in five actions. `lock` stays out: SUPER+L covers it.
        session.actions = [
          {
            action = "logout";
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

      shell.polkit_agent = true;

      # phonto plays the wallpapers (home-manager/phonto.nix), and Noctalia's is a layer-shell
      # surface on the same layer: exactly one of the two may be enabled.
      wallpaper.enabled = false;

      notification.enable_daemon = true;

      audio.enable_sounds = true;

      calendar.enabled = true;

      dock.enabled = false;

      # The DP panels expose nothing under /sys/class/backlight, so brightness needs DDC/CI:
      # Noctalia shells out to `ddcutil` over /dev/i2c-* (hardware.i2c).
      brightness.enable_ddcutil = true;

      # Session lock unlocks through PAM service "login" (hardcoded) and the setuid unix_chkpwd
      # helper: no non-PAM fallback, so test SUPER+L on the very first session. Holds a sleep
      # inhibitor, so suspend locks first.
      lockscreen = {
        enabled = true;
        lock_before_suspend = true;
        fingerprint = false; # no fprintd on this host
      };

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

      bar.default = {
        capsule = true;
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
        hide_when_no_media = true;
        show_progress = true;
        title_scroll = "always";
      };

      # checkConfig logs `unrecognized widget type` for this one: the plugin registry is cloned into
      # the state dir at runtime, and the build sandbox has none of it. It exits 0 on warnings.
      widget.file-search.type = "nightwatch75/file-search:file-search";

      # The widget-editor layout is absolute and per-output: this describes the 2560x1440 pair on
      # DP-1/DP-2, so moving a widget means redoing it in the editor. schema_version is its stamp.
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

      # "all" would git-clone the official and community sources on startup and every 6 h.
      plugins.auto_update = "none";
      plugins.enabled = [ "nightwatch75/file-search" ];
    };
  };

  # NixOS `programs.noctalia` stays disabled on purpose: it would install a second noctalia.service.
}
