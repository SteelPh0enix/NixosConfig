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
  };
}
