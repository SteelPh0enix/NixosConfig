{ username, ... }:
{
  users.groups = {
    "${username}" = { };
    pcap = { };
    wireshark = { };
  };

  users.users.${username} = {
    home = "/home/${username}";
    isNormalUser = true;
    extraGroups = [
      username
      "users"
      "wheel"
      "video"
      "networkmanager"
      "render"
      "pcap"
      "wireshark"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoBzFN664gkpNbjnvTkMaO2zlI0rQTto1gJ+B26fbvO phoen@SteelPh0enixROG"
    ];
  };
}
