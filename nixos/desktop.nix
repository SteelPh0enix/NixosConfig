{ pkgs, ... }:
{
  services.xserver.enable = true;

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.settings.General.DisplayServer = "wayland";

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "steelph0enix";

  environment.systemPackages = with pkgs; [
    hardinfo2
    kdePackages.kcalc
    kdePackages.kclock
    kdePackages.ksystemlog
    kdiff3
    wayland-utils
    wl-clipboard
    xclip
  ];
}
