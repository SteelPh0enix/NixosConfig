{ lib, settings, ... }:
let
  inherit (settings) userName;

  # Coral Edge TPU boards: every boot mode needs raw USB/hidraw access without root.
  # `serial` adds the stable /dev/coral_micro_UART* symlink, `autosuspend` keeps the
  # application-mode device from being runtime-suspended mid-flash.
  tpuModes = [
    {
      desc = "ROM bootloader";
      vendor = "1fc9";
      product = "013d";
    }
    {
      desc = "Flashloader";
      vendor = "15a2";
      product = "0073";
    }
    {
      desc = "Bootloader mode ID";
      vendor = "18d1";
      product = "9307";
    }
    {
      desc = "Application mode ID";
      vendor = "18d1";
      product = "9308";
      serial = true;
      autosuspend = true;
    }
    {
      desc = "Legacy ID";
      vendor = "18d1";
      product = "93fe";
    }
    {
      desc = "Legacy ID";
      vendor = "18d1";
      product = "93ff";
      serial = true;
    }
  ];

  tpuRules =
    d:
    let
      match = ''ATTRS{idVendor}=="${d.vendor}", ATTRS{idProduct}=="${d.product}"'';
    in
    ''
      # ${d.desc}
      SUBSYSTEM=="usb",  ${match}, MODE="0666", GROUP="plugdev"
      KERNEL=="hidraw*", ${match}, MODE="0666", GROUP="plugdev"
    ''
    + lib.optionalString (d.autosuspend or false) ''
      SUBSYSTEM=="usb",  ${match}, TEST=="power/control", ATTR{power/control}="auto"
      SUBSYSTEM=="usb",  ${match}, TEST=="power/autosuspend_delay_ms", ATTR{power/autosuspend_delay_ms}="1000"
    ''
    + lib.optionalString (d.serial or false) ''
      KERNEL=="ttyACM*", ${match}, MODE="0666", SYMLINK+="coral_micro_UART-$attr{serial}"
    '';

  # Moondrop Dawn Pro 2: access for ${userName} only, no group membership needed.
  audioRules =
    d:
    let
      match = ''ATTRS{idVendor}=="${d.vendor}", ATTRS{idProduct}=="${d.product}"'';
    in
    ''
      # Moondrop Dawn Pro 2
      SUBSYSTEM=="usb",    ${match}, MODE="0660", OWNER="${userName}"
      SUBSYSTEM=="sound",   ${match}, MODE="0660", OWNER="${userName}"
      KERNEL=="hidraw*",    ${match}, MODE="0660", OWNER="${userName}"
    '';
in
{
  boot.kernelModules = [ "kvm-amd" ];

  boot.kernelParams = [
    "microcode.amd_sha_check=off"
    "amd_pstate=active"
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
    overdrive.enable = true; # also what LACT uses to change clocks/voltages
  };

  # /dev/i2c-* + i2c-dev, so DDC/CI brightness control works (Noctalia's brightness keys).
  hardware.i2c.enable = true;

  # Installs lact, its systemd.packages units, and wants lactd at multi-user.target.
  services.lact.enable = true;

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
    # Any NXP (15a2) device in download mode, whatever the product ID.
    ATTRS{idVendor}=="15a2", MODE="666"

    ${lib.concatStringsSep "\n" (map tpuRules tpuModes)}
    ${audioRules {
      vendor = "35d8";
      product = "011d";
    }}
  '';

  environment.variables.AMD_VULKAN_ICD = "RADV";

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

  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "kernel.sched_cfs_bandwidth_slice_us" = 3000;
    "net.core.netdev_max_backlog" = 65536;
    "net.ipv4.tcp_fastopen" = 3;
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
