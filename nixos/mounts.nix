{
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 32 * 1024;
      randomEncryption.enable = true;
    }
  ];

  fileSystems."/mnt/NAS" = {
    device = "/dev/disk/by-uuid/24261497-6b99-47ea-86a3-ef4ab0133bad";
    fsType = "ext4";
    options = [
      "defaults"
      "noatime"
      "barrier=1"
      "data=ordered"
      "errors=remount-ro"
      "commit=300"
      "nofail"
      "user"
    ];
  };

  fileSystems."/mnt/NAS2" = {
    device = "/dev/disk/by-uuid/a6133d4a-cca8-42df-aaf6-429fbe2fd2d9";
    fsType = "ext4";
    options = [
      "defaults"
      "noatime"
      "barrier=1"
      "data=ordered"
      "errors=remount-ro"
      "commit=300"
      "nofail"
      "user"
    ];
  };
}
