{ pkgs, ... }:
{
  services.xserver = {
    enable = true;
    videoDrivers = [ "amdgpu" ];
    desktopManager.xfce.enable = true;
    # XRDP starts its own Xorg; no local greeter is needed.
    displayManager.lightdm.enable = false;
  };

  environment.systemPackages = with pkgs; [
    hardinfo2
    xclip
  ];
}
