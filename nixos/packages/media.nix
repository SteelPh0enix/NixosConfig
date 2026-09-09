{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    ffmpeg-full
    vulkan-tools
    websocat
  ];
}
