{
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  security.rtkit.enable = true;

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };
}
