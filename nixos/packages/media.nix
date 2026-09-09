{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    ffmpeg-full # conversion/recording CLI (obs, mpv and conform use their own ffmpeg)
    vulkan-tools # vulkaninfo
    websocat
  ];
}
