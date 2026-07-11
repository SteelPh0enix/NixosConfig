{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gst_all_1.gst-libav
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-ugly
    gst_all_1.gstreamer
    vk-bootstrap
    vkdevicechooser
    vkdisplayinfo
    vkmark
    vulkan-extension-layer
    vulkan-helper
    vulkan-tools
    vulkan-utility-libraries
    websocat

    ffmpeg-full
  ];
}
