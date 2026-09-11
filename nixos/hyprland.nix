{
  pkgs,
  lib,
  settings,
  ...
}:
{
  # uwsm owns graphical-session.target and the session environment,
  # so the home-manager module must keep `systemd.enable = false`.
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true; # XWayland only; Xorg itself stays off
  };

  # Lock screen, idle and screen blanking belong to Noctalia (hyprland/noctalia.nix), so
  # programs.hyprlock stays off - it would also force nixpkgs services.hypridle, i.e. a second
  # idle daemon.

  services.displayManager = {
    # Inert under greetd (it uses initial_session / its own persisted choice),
    # but pinned and build-time asserted against the sessions the profile provides.
    defaultSession = "hyprland-uwsm";

    noctalia-greeter = {
      enable = true; # sets services.greetd.enable + default_session.command
      settings = {
        keyboard.layout = "pl";
        cursor.size = 24;
      };
      cursorTheme = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
      };
    };
  };

  # This greeter has no autoLogin support, so state it directly. Mirrors upstream
  # hyprland-uwsm.desktop: `uwsm start -e -D Hyprland hyprland.desktop`.
  # Presence of initial_session also makes services.greetd.restart default to false.
  services.greetd.settings.initial_session = {
    user = settings.userName;
    command = "${lib.getExe pkgs.uwsm} start -e -D Hyprland hyprland.desktop";
  };

  # Electron (discord, element, obsidian, teams, drawio, heroic, jellyfin-desktop)
  # otherwise falls back to XWayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # org.freedesktop.secrets: Chromium safe storage, remmina's password store, secret-tool and
  # Noctalia's encrypted clipboard history. Nothing else here provides that name.
  # D-Bus-activatable; it also registers itself as the Secret portal.
  services.gnome.gnome-keyring.enable = true;

  # gcr-ssh-agent is switched on by gnome-keyring.enable and conflicts with the existing
  # programs.ssh.startAgent, so keep the plain OpenSSH agent.
  services.gnome.gcr-ssh-agent.enable = false;

  # Noctalia's battery and power-profile widgets require UPower; the option defaults to false.
  services.upower.enable = true;

  # programs.ssh.enableAskPassword defaults to services.xserver.enable, so without this line
  # SSH_ASKPASS quietly disappears instead of prompting in a GUI.
  programs.ssh.enableAskPassword = true;
  programs.ssh.askPassword = "${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass"; # GTK3 (OpenSSH contrib)
}
