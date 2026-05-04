{ lib, ... }:
{
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" ];

  boot.kernelParams = [
    "microcode.amd_sha_check=off"
    "amd_pstate=active"
    "amdgpu.ppfeaturemask=0xffffffff"
    "amdgpu.gpu_recovery=1"
    "amdgpu.gfx_off=0"
    "amdgpu.runpm=0"
    "amdgpu.tmz=0"
    "amdgpu.noretry=0"
    "split_lock_detect=off"
  ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = lib.mkForce false;
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

  powerManagement.cpuFreqGovernor = "performance";

  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "kernel.sched_cfs_bandwidth_slice_us" = 3000;
    "kernel.sched_latency_ns" = 1000000;
    "kernel.sched_min_granularity_ns" = 100000;
    "kernel.sched_wakeup_granularity_ns" = 200000;
    "net.core.netdev_max_backlog" = 65536;
    "net.ipv4.tcp_fastopen" = 3;
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
