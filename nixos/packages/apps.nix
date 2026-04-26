{ pkgs, pkgsUnstable, ... }:
{
  environment.systemPackages = with pkgs; [
    blueman
    zenity

    pkgsUnstable.btop-rocm
    pkgsUnstable.flatpak
    pkgsUnstable.nerd-font-patcher
    pkgsUnstable.sqlite
  ];
}
