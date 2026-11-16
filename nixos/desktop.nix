{
  pkgs,
  settings,
  ...
}:
{
  programs.niri.enable = true;

  # niri starts XWayland on demand, but its module leaves the binary off; Xorg stays off entirely.
  programs.xwayland.enable = true;

  services.displayManager = {
    # Inert under greetd, which uses initial_session; pinned as a build-time check instead.
    defaultSession = "niri";

    noctalia-greeter = {
      enable = true;
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

  # This greeter has no autoLogin support, so niri.desktop's Exec is stated here, through a login
  # shell so /etc/profile loads environment.sessionVariables. It also defaults greetd.restart off.
  services.greetd.settings.initial_session = {
    user = settings.userName;
    command = "${pkgs.niri}/bin/niri-session";
  };

  # Electron apps otherwise fall back to XWayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  services.gnome.gnome-keyring.enable = true;

  # gcr-ssh-agent is switched on by gnome-keyring.enable and conflicts with startAgent.
  services.gnome.gcr-ssh-agent.enable = false;

  services.upower.enable = true;

  # Defaults to services.xserver.enable, so SSH_ASKPASS would quietly disappear without it.
  programs.ssh.enableAskPassword = true;
  programs.ssh.askPassword = "${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass";
}
