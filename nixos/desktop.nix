{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.desktopManager.xfce.enable = true;

  qt.enable = true;
  qt.platformTheme = "gtk2";
  qt.style = "bb10dark";

  environment.systemPackages = with pkgs; [
    hardinfo2
    xclip
  ];
}
