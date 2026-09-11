# no `pkgs` needed: the compositor and the portal come from the system module
{ ... }:
{
  imports = [
    ./noctalia.nix
    ./services.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = null; # installed system-wide by programs.hyprland
    portalPackage = null; # likewise

    # Combo A: uwsm starts graphical-session.target; HM must not fight it.
    systemd.enable = false;

    configType = "lua";

    settings = {
      # EVERY config group must sit under `settings.config`: the only way to set config
      # values is the single hl.config call (no hl.general / hl.input / hl.misc).
      config = {
        general = {
          gaps_in = 6;
          gaps_out = 12; # default 20
          border_size = 2; # default 1
          resize_on_border = true;
          col.active_border = "rgba(33ccffee)";
          col.inactive_border = "rgba(595959aa)";
        };
        decoration = {
          rounding = 8; # default 0; blur and shadows are on by default
          dim_inactive = true;
        };
        input.kb_layout = "pl"; # binds use the first layout; digits are unmodified on `pl`
        # int, not bool (0 nothing / 1 previous ws / also-when-moving). `hyprctl getoption
        # binds:workspace_back_and_forth` prints the accepted values for any option.
        binds.workspace_back_and_forth = 1;
        dwindle.preserve_split = true;
        render.direct_scanout = 1; # amdgpu: lower latency for a lone fullscreen window
        cursor = {
          no_warps = true;
          hide_on_key_press = true;
          min_refresh_rate = 48; # VRR floor while the cursor moves in fullscreen; set per panel
        };
        misc = {
          disable_hyprland_logo = true;
          force_default_wallpaper = 0; # Noctalia draws the wallpaper
          disable_autoreload = true; # generated file; shell.nix reloads it
          mouse_move_enables_dpms = true;
          key_press_enables_dpms = true;
          font_family = "Berkeley Mono"; # it is `misc`, not `general`
          vrr = 3; # 0 off / 1 on / 2 fullscreen / 3 fullscreen + video|game
        };
        ecosystem.no_update_news = true; # nixpkgs decides when Hyprland updates
        ecosystem.no_donation_nag = true;
      };

      # The catch-all (`output = ""`, upstream's own default rule) stays first; per-output rules
      # from `hyprctl monitors` are appended below it and override/merge field by field (see
      # https://wiki.hypr.land/Configuring/Basics/Monitor-Rules/). mode/position/scale are STRING
      # fields in the Lua API; `scale = "auto"` becomes a fixed number for a HiDPI panel.
      monitor = [
        {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = "auto";
        }
      ];

      # hl.env(name, value, importToDbus) - the third argument is what gets the theme into
      # systemd-started services.
      env = [
        {
          _args = [
            "XCURSOR_SIZE"
            "24"
          ];
        }
        {
          _args = [
            "XCURSOR_THEME"
            "Bibata-Modern-Classic"
            true
          ];
        }
        {
          _args = [
            "GDK_BACKEND"
            "wayland"
          ];
        }
      ];
    };

    # Keybinds and rules stay in raw Lua: HM's renderer needs mkLuaInline for every dispatch.
    # A path is symlinked; `autoLoad = true` emits the `require(...)` line.
    extraLuaFiles = {
      bindings.content = ./bindings.lua;
      rules.content = ./rules.lua;
    };
  };

  # `package = null` also skips HM's generated hypr/.luarc.json; point the Lua LSP at the stubs
  # the NixOS module exposes via `pathsToLink = [ "/share/hypr" ]`.
  xdg.configFile."hypr/.luarc.json".text = builtins.toJSON {
    workspace.library = [ "/run/current-system/sw/share/hypr/stubs" ];
    diagnostics.globals = [ "hl" ];
  };
}
