{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    blueman
    zenity
    btop-rocm
    flatpak
    nerd-font-patcher
    sqlite
  ];
}
