{ pkgs, ... }:
{
  users.groups = {
    steelph0enix = { };
    pcap = { };
    wireshark = { };
    docker = { };
  };

  users.users.steelph0enix = {
    home = "/home/steelph0enix";
    isNormalUser = true;
    extraGroups = [
      "steelph0enix"
      "users"
      "wheel"
      "video"
      "networkmanager"
      "render"
      "pcap"
      "wireshark"
      "docker"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoBzFN664gkpNbjnvTkMaO2zlI0rQTto1gJ+B26fbvO phoen@SteelPh0enixROG"
    ];
  };

  users.defaultUserShell = pkgs.fish;
  nix.settings.trusted-users = [ "steelph0enix" ];
}
