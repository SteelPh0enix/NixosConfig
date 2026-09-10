{ pkgs, settings, ... }:
{
  # Wayland-only session, but Plasma still reads services.xserver.xkb (its layout is what
  # `environment.etc."X11/xkb"` and SDDM are built from).
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = settings.userName;

  # Only the Plasma bits that have to sit in the system profile: KIO slaves and Dolphin/
  # System-Settings plugins are registered through the merged profile, signond is a D-Bus
  # service. The session itself (kwin, plasma-workspace, kio-{admin,extras,fuse}, phonon-vlc,
  # kdeplasma-addons, xdg-desktop-portal-kde, ...) is installed by services.desktopManager.plasma6,
  # and the apps (kcalc, filelight, vlc, ...) live in home-manager/packages.nix.
  environment.systemPackages = with pkgs.kdePackages; [
    kaccounts-integration
    kaccounts-providers
    kdenetwork-filesharing
    kdialog
    kidentitymanagement
    kio-gdrive
    plasma-wayland-protocols
    sddm-kcm
    signon-kwallet-extension
    signond
    wayland
    wayland-protocols
  ];

  qt.platformTheme = "kde";

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };
}
