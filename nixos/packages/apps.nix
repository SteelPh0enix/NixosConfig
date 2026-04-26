{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    btop-rocm
    espeak
    nerd-font-patcher
    obsidian
    sqlite
    steam-tui
    steamcmd
    weechat
    zenity
  ];
}
