{
  fileSystems."/run/media/steelph0enix/Windows" = {
    device = "/dev/disk/by-uuid/8CCECE61CECE4366";
    fsType = "ntfs-3g";
    options = [
      "defaults"
      "users"
      "nofail"
      "rw"
      "uid=1000"
      "gid=1000"
      "dmask=007"
      "fmask=117"
    ];
  };

  fileSystems."/run/media/steelph0enix/SSD" = {
    device = "/dev/disk/by-uuid/1030801630800546";
    fsType = "ntfs-3g";
    options = [
      "defaults"
      "users"
      "nofail"
      "exec"
      "rw"
      "uid=1000"
      "gid=1000"
      "dmask=007"
      "fmask=117"
    ];
  };

  fileSystems."/run/media/steelph0enix/HDD" = {
    device = "/dev/disk/by-uuid/5E76D87176D84B81";
    fsType = "ntfs-3g";
    options = [
      "defaults"
      "users"
      "nofail"
      "exec"
      "rw"
      "uid=1000"
      "gid=1000"
      "dmask=007"
      "fmask=117"
    ];
  };

  fileSystems."/run/media/steelph0enix/NVMe" = {
    device = "/dev/disk/by-uuid/01D80FB32E38B2E0";
    fsType = "ntfs-3g";
    options = [
      "defaults"
      "users"
      "nofail"
      "exec"
      "rw"
      "uid=1000"
      "gid=1000"
      "dmask=007"
      "fmask=117"
    ];
  };

  fileSystems."/run/media/steelph0enix/NAS_HDD" = {
    device = "//steelph0enix.framework/NAS_HDD";
    fsType = "cifs";
    options =
      let
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,user,users";
      in
      [ "${automount_opts},credentials=/home/steelph0enix/smb-secrets,uid=1000,gid=100" ];
  };
}
