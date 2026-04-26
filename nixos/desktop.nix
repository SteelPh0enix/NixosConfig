{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.settings.General.DisplayServer = "wayland";

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "steelph0enix";

  environment.systemPackages = with pkgs; [
    hardinfo2
    kdePackages.filelight
    kdePackages.isoimagewriter
    kdePackages.kaccounts-integration
    kdePackages.kaccounts-providers
    kdePackages.kcalc
    kdePackages.kcharselect
    kdePackages.kclock
    kdePackages.kcolorchooser
    kdePackages.kdenetwork-filesharing
    kdePackages.kdeplasma-addons
    kdePackages.kdialog
    kdePackages.kidentitymanagement
    kdePackages.kio-admin
    kdePackages.kio-extras
    kdePackages.kio-fuse
    kdePackages.kio-gdrive
    kdePackages.ksystemlog
    kdePackages.kweather
    kdePackages.phonon-vlc
    kdePackages.plasma-wayland-protocols
    kdePackages.sddm-kcm
    kdePackages.signon-kwallet-extension
    kdePackages.signond
    kdePackages.sweeper
    kdePackages.wayland
    kdePackages.wayland-protocols
    kdePackages.xdg-desktop-portal-kde
    kdiff3
    vlc
    wayland-utils
    wl-clipboard
    xclip
  ];

  qt.platformTheme = "kde";
  qt.style = "bb10dark";

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };
}
