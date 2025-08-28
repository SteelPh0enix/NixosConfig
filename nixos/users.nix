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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoBzFN664gkpNbjnvTkMaO2zlI0rQTto1gJ+B26fbvO phoen@SteelPh0enixROG"
    ];
  };
}
