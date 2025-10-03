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
      "noauto"
      "nofail"
      "nosuid"
      "rw"
      "user"
      "x-gvfs-show"
    ];
  };
}
