{ pkgs, ... }:
{
  users.groups = {
    steelph0enix = { };
    pcap = { };
    wireshark = { };
    docker = { };
    vboxsf = {};
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
      "vboxsf"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHhtZlWrQqOkhNd68qrRDN1oYey1sf37sjM1LMcc+zfz phoen@SteelPh0enixROG"
    ];
  };

  users.defaultUserShell = pkgs.fish;
  nix.settings.trusted-users = [ "steelph0enix" ];
}
