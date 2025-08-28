{ ... }:
{
  fileSystems."/run/media/steelph0enix/Windows" = {
    device = "/dev/disk/by-uuid/8CCECE61CECE4366";
    fsType = "ntfs-3g";
  };
  fileSystems."/run/media/steelph0enix/SSD" = {
    device = "/dev/disk/by-uuid/1030801630800546";
    fsType = "ntfs-3g";
  };
  fileSystems."/run/media/steelph0enix/HDD" = {
    device = "/dev/disk/by-uuid/5E76D87176D84B81";
    fsType = "ntfs-3g";
  };
  fileSystems."/run/media/steelph0enix/NVMe" = {
    device = "/dev/disk/by-uuid/01D80FB32E38B2E0";
    fsType = "ntfs-3g";
  };
}
