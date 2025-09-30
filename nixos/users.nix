{ pkgs, ... }:
{
  users.groups = {
    steelph0enix = { };
    pcap = { };
    wireshark = { };
    docker = { };
    vboxusers = { };
    plugdev = { };
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
      "vboxusers"
      "plugdev"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID7HEYiuWVQP3BcNDibe5cwVuL081u1Noos4OAuyWVBb FrameworkPC SSH"
    ];
  };

  users.defaultUserShell = pkgs.fish;
  nix.settings.trusted-users = [ "steelph0enix" ];

  security.pam.loginLimits = [
    {
      domain = "*";
      item = "memlock";
      value = "infinity";
    }
  ];
}
