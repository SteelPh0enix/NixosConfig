{ username, ... }:
{
  users.groups = {
    "${username}" = { };
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
    ];
  };
}
