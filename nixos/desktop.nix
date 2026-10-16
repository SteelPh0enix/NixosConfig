{
  pkgs,
  settings,
  ...
}:
{
  programs.niri.enable = true;

  # niri starts XWayland on demand through xwayland-satellite (home-manager/niri), but its module
  # deliberately leaves the Xwayland binary off, and Xorg itself stays off entirely.
  programs.xwayland.enable = true;

  # Lock screen, idle and screen blanking belong to Noctalia (home-manager/noctalia.nix), so no
  # swaylock/hypridle-style daemon is installed beside it.

  services.displayManager = {
    # Inert under greetd (it uses initial_session / its own persisted choice),
    # but pinned and build-time asserted against the sessions the profile provides.
    defaultSession = "niri";

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

  # This greeter has no autoLogin support, so state it directly: the Exec of niri.desktop. Run
  # through a login shell (so /etc/profile loads `environment.sessionVariables`) before starting
  # niri.service, and import that environment into systemd and D-Bus on the way.
  # Presence of initial_session also makes services.greetd.restart default to false.
  services.greetd.settings.initial_session = {
    user = settings.userName;
    command = "${pkgs.niri}/bin/niri-session";
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
