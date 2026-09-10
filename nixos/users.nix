{ pkgs, settings, ... }:
{
  # Needed by the udev rules in hardware.nix (GROUP="plugdev").
  users.groups.plugdev = { };

  users.users.${settings.userName} = {
    home = "/home/${settings.userName}";
    isNormalUser = true;
    extraGroups = [
      "audio"
      "docker"
      "networkmanager"
      "pcap"
      "plugdev"
      "render"
      "vboxusers"
      "video"
      "wheel"
      "wireshark"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoBzFN664gkpNbjnvTkMaO2zlI0rQTto1gJ+B26fbvO phoen@SteelPh0enixROG"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIkI09ESn4YENxKD+vjmIggbLaoOL3GQFoep0H4XX7le desktoppc"
    ];
  };

  # Primary shell; `programs.fish.enable` (nixos/packages) is what puts it in /etc/shells.
  users.defaultUserShell = pkgs.fish;

  security.pam.loginLimits = [
    {
      domain = "*";
      item = "memlock";
      value = "infinity";
    }
    {
      domain = "*";
      item = "nofile";
      value = "1048576";
    }
  ];
}
