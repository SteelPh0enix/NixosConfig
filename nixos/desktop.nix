{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.desktopManager.xfce.enable = true;

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "steelph0enix";

  qt.enable = true;
  qt.platformTheme = "gtk2";
  qt.style = "bb10dark";

  environment.systemPackages = with pkgs; [
    hardinfo2
    xclip
  ];
}
