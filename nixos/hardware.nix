{
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.amdgpu = {
    amdvlk.enable = true;
    amdvlk.support32Bit.enable = true;
    opencl.enable = true;
  };

  # force RADV
  environment.variables.AMD_VULKAN_ICD = "RADV";
  environment.variables.VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    media-session.enable = true;
  };
}
