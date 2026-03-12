{ pkgs, ... }:
{
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=0
    options snd_hda_intel power_save_controller=N
  '';

  boot.kernelParams = [
    "kvm.enable_virt_at_load=0"
    "microcode.amd_sha_check=off"
  ];

  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.amdgpu = {
    opencl.enable = true;
    overdrive.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  services.udev.extraRules = ''
    # ROM bootloader
    SUBSYSTEM=="usb",  ATTRS{idVendor}=="1fc9", ATTRS{idProduct}=="013d", MODE="0666", GROUP="plugdev"
    KERNEL=="hidraw*", ATTRS{idVendor}=="1fc9", ATTRS{idProduct}=="013d", MODE="0666", GROUP="plugdev"

    # Flashloader
    ATTRS{idVendor}=="15a2",MODE="666"
    SUBSYSTEM=="usb",  ATTRS{idVendor}=="15a2", ATTRS{idProduct}=="0073", MODE="0666", GROUP="plugdev"
    KERNEL=="hidraw*", ATTRS{idVendor}=="15a2", ATTRS{idProduct}=="0073", MODE="0666", GROUP="plugdev"

    # Bootloader mode ID
    SUBSYSTEM=="usb",  ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="9307", MODE="0666", GROUP="plugdev"
    KERNEL=="hidraw*", ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="9307", MODE="0666", GROUP="plugdev"

    # Application mode ID
    SUBSYSTEM=="usb",  ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="9308", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb",  ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="9308", TEST=="power/control", ATTR{power/control}="auto"
    SUBSYSTEM=="usb",  ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="9308", TEST=="power/autosuspend_delay_ms", ATTR{power/autosuspend_delay_ms}="1000"
    KERNEL=="ttyACM*", ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="9308", MODE="0666", SYMLINK+="coral_micro_UART-$attr{serial}"

    # Legacy IDs
    SUBSYSTEM=="usb",  ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="93fe", MODE="0666", GROUP="plugdev"
    KERNEL=="hidraw*", ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="93fe", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb",  ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="93ff", MODE="0666", GROUP="plugdev"
    KERNEL=="ttyACM*", ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="93ff", MODE="0666", SYMLINK+="coral_micro_UART-$attr{serial}"
  '';

  services.pulseaudio.extraConfig = "unload-module module-suspend-on-idle";

  # force RADV
  environment.variables.AMD_VULKAN_ICD = "RADV";
  environment.variables.VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber = {
      enable = true;
      extraConfig = {
        pipewire."92-low-latency" = {
          "context.properties" = {
            "default.clock.rate" = 48000;
            "default.clock.quantum" = 32;
            "default.clock.min-quantum" = 32;
            "default.clock.max-quantum" = 32;
          };
        };
        bluetoothEnhancements = {
          "monitor.bluez.properties" = {
            "bluez5.enable-sbc-xq" = true;
            "bluez5.enable-msbc" = true;
            "bluez5.enable-hw-volume" = true;
            "bluez5.hfphsp-backend" = "native";
            "bluez5.codecs" = [
              "sbc"
              "sbc_xq"
              "aac"
              "ldac"
              "lc3"
              "lc3plus_h3"
              "aptx"
              "aptx_hd"
              "aptx_ll"
              "aptx_ll_duplex"
            ];
            "bluez5.roles" = [
              "hsp_hs"
              "hsp_ag"
              "hfp_hf"
              "hfp_ag"
              "a2dp_sink"
              "a2dp_source"
              "bap_sink"
              "bap_source"
            ];
          };
        };
      };
    };
  };
}
