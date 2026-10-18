_: {
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" ];

  boot.kernelParams = [
    "microcode.amd_sha_check=off"
    "amd_pstate=active"
    "amdgpu.gpu_recovery=1"
    "amdgpu.gfx_off=0"
    "amdgpu.runpm=0"
    "amdgpu.tmz=0"
    "amdgpu.noretry=0"
    "amdgpu.gttsize=126976"
    "amdgpu.lockup_timeout=600000"
    "split_lock_detect=off"
    "amd_iommu=off"
    "ttm.pages_limit=32505856"
    # llama.cpp and the JVM never madvise(MADV_HUGEPAGE), so the `madvise` default of the kernel
    # would leave their heaps on 4K pages.
    "transparent_hugepage=always"
  ];

  boot.extraModprobeConfig = ''
    options amdgpu gttsize=126976
    options amdgpu vm_fragment_size=8
    options ttm pages_limit=32505856
    options ttm page_pool_size=32505856
  '';

  hardware.enableRedistributableFirmware = true;
  # AMD microcode comes from ucodenix (`nixos/services.nix`), whose blobs are fresher than
  # linux-firmware's; `microcode.amd_sha_check=off` above is what lets them load.
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
    # Almost the whole unified pool is committed by the inference engine and most of it is amdgpu GTT,
    # which sits on no LRU, so there is little to reclaim and it must start early. The default reserve is
    # 66 MiB: the kernel ran to zero free and failed allocations inside its own swap path. Waking kswapd
    # a percent earlier keeps that reclaim off the allocating process, which is where a stall becomes a
    # hang. Both are pinned so a kernel swap cannot move them back.
    #
    # overcommit_memory stays at the `1` the redis module asks for: heuristic (0) is still optimistic and
    # would not have refused anything here, while strict (2) counts address space and no engine that
    # reserves 240 GiB of it could load at all.
    "vm.min_free_kbytes" = 2097152;
    "vm.watermark_scale_factor" = 100;
    "kernel.sched_cfs_bandwidth_slice_us" = 3000;
    "net.core.netdev_max_backlog" = 65536;
    "net.ipv4.tcp_fastopen" = 3;
    # XanMod picks bbr by default; pinned here so a kernel swap cannot move it under us.
    "net.ipv4.tcp_congestion_control" = "cubic";
  };

  zramSwap = {
    enable = true;
    # Half of RAM let the kernel accept ~60 GiB of compression instead of failing: minutes of engine
    # pages being squeezed while zram needed RAM it no longer had, then a global OOM kill. 10 GiB covers
    # genuine outliers and turns the rest into a fast, visible failure.
    memoryPercent = 10;
  };

  services.irqbalance.enable = true;
  services.fstrim.enable = true;
}
