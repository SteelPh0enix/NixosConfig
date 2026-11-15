_:
let
  gttSize = 126976;
  ttmPages = 32505856;
in
{
  boot.initrd.kernelModules = [ "amdgpu" ];

  boot.kernelParams = [
    "microcode.amd_sha_check=off"
    "amd_pstate=active"
    "amdgpu.gpu_recovery=1"
    "amdgpu.gfx_off=0"
    "amdgpu.runpm=0"
    "amdgpu.tmz=0"
    "amdgpu.noretry=0"
    "amdgpu.gttsize=${toString gttSize}"
    "amdgpu.lockup_timeout=600000"
    "split_lock_detect=off"
    "amd_iommu=off"
    "ttm.pages_limit=${toString ttmPages}"
    # llama.cpp and the JVM never madvise(MADV_HUGEPAGE).
    "transparent_hugepage=always"
  ];

  boot.extraModprobeConfig = ''
    options amdgpu gttsize=${toString gttSize}
    options amdgpu vm_fragment_size=8
    options ttm pages_limit=${toString ttmPages}
    options ttm page_pool_size=${toString ttmPages}
  '';

  hardware.enableRedistributableFirmware = true;
  # ucodenix's blobs are fresher than linux-firmware's; the sha_check parameter lets them load.
  hardware.graphics.enable = true;
  hardware.amdgpu.overdrive.enable = true;

  environment.variables.AMD_VULKAN_ICD = "RADV";

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;
      extraConfig = {
        pipewire."92-low-latency" = {
          "context.properties" = {
            "default.clock.rate" = 48000;
            "default.clock.quantum" = 256;
            "default.clock.min-quantum" = 256;
            "default.clock.max-quantum" = 256;
          };
        };
      };
    };
  };

  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    # GTT pages sit on no LRU and must be reclaimed early. overcommit_memory stays at the redis
    # module's `1`: strict counts the engines' 240 GiB of reserved address space and nothing loads.
    "vm.min_free_kbytes" = 2097152;
    "vm.watermark_scale_factor" = 100;
    "kernel.sched_cfs_bandwidth_slice_us" = 3000;
    "net.core.netdev_max_backlog" = 65536;
    "net.ipv4.tcp_fastopen" = 3;
    # XanMod defaults to bbr; pinned so a kernel swap cannot change it.
    "net.ipv4.tcp_congestion_control" = "cubic";
  };

  zramSwap = {
    enable = true;
    # 10% (about 12 GiB) covers genuine outliers. Half of RAM let the kernel accept ~60 GiB of
    # compression it no longer had RAM to hold, ending in a global OOM kill.
    memoryPercent = 10;
  };

  services.irqbalance.enable = true;
  services.fstrim.enable = true;
}
