{ pkgs, ... }:
{
  # Only define custom groups not auto-created by NixOS modules
  users.groups = {
    steelph0enix = { };
    quake = { };
    samba = { };
  };

  users.users = {
    steelph0enix = {
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
        "samba"
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID7HEYiuWVQP3BcNDibe5cwVuL081u1Noos4OAuyWVBb FrameworkPC SSH"
      ];
    };

    quake = {
      home = "/home/quake";
      isNormalUser = true;
      extraGroups = [
        "quake"
        "users"
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
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAEAQC0xPahpIbvWIZ614gO/O2qGc5vai6RXUamVwZSNPqj85/ecODmW7G64TQLhNfu2WQPjqy/L6iifq8P8vaeoHe1NrWj09tv4XmAjTzHTxm+30Q3T5V4doDyw2b7ifal+TVStiAtB88LarY953eTCJ288/UP80bRK6GPHPd/pP/JN2i7bRFxt58qkPGvNlOBFhrh7yTfVn08n6nukdRoln44ymEHUmnGhweSZ7RlGG45NNxEFeFwQMy4tVNefj0/o/aqKNP24AkCqs2BRKDWcvGum3lJZcmRVNIFGhgMOj6Z+gSn7m4v7YKiAdoK1P+e8IaJbe2pPgqoTjBZibuXU2p4guf+SDG1DuzgEZp69nn23A3UFr4vMiFTN11LXOEbHGZdXdPchnzUSz/w8fonLW7vC37eH35FFgR78VuSYiVV5o4Q0dF5DQZutuszGQyPrUG2QAXmL+PLOI24lI8bogJ2Uai2BLqT1q1oq//vGIrV7kgF19o+qe8QWttvRxxiQvnf9ag2YkAF9TY95jYk9cTXOn8W8o+0ITfYPSvWVfwKc/YMw4vD2xllLYgiIfxY8eyzICL+MPyZGaj4aS5Eac7O2UMxj+kOKA7XSglBdCEGaSjxd/SqUpu0Onn5RnajG7M06H2+BFo8iJx5u4uiD38f1wfO73T2bzXl01q7zivVOKP2rAtiHv/A44IvFaoUAsQ/nGMuW9RmuC2mfFLrShOfUajLqhoCSqzPziK/xoPGi+xFOTHjcNJrG0/WDAuia5k0nLbi8lsE2yD20H9csqhGJ29ooOuOvMfBFlRpzfg6wfuA+VI36H4kna8em71iqVyY5E5GgtvscBBteE3e6OHelUCOpMd04hn11quLAX5hmu1d63Yvab7NRM2oVQUjh4d8ZzR1nzYoSba8nvue6VIL9tGdi0Hqm5RSw3gyXnRu7RREbquPThzYXibyX/YU0te7UKsQkrGGeBDzAmYn6Aq+ljbbCRTUZxh0Qaq6DZ4Lm94ecryBL9YAZ1d8L1KP38ftorh5UsPFZxkgSsD/iuEk4h0vrcN87QurE5pRypCygNRwf2tu71WThNtkxVH/pLhxGCkDR5MXwKcZIas4DupWmE2ZmxRH7Hv/sbUZ2QUwTljrb81ZJQh5RvdRfYlI3O2NRiD/PL7uSq8jG7FDe7KLvJ2SpbigZRyLNWckNw5QzY+1sPg7K+M5XkYzu19bI1XWWvY1FMFTizOvXNMvtToao50vEMZG00VxWP/cUIDdk9GGNqVA/RJbAeki0UbMKETmYwLmx+gyj+xpbfPf7ZYRDt354eE2MoIbYcZPjKSI/Ly+64Qysw4LcVE084bXLvqf1A5cyHJIBRl7qJx3pNll Wojtas SSH"
      ];
    };

    # Service users - groups auto-created by NixOS modules
    jellyfin = {
      isNormalUser = false;
      group = "users";
      extraGroups = [
        "render"
        "video"
      ];
    };

    qbittorrent = {
      isNormalUser = false;
      group = "users";
    };

    gitea = {
      isNormalUser = false;
      group = "gitea";
    };
  };

  users.defaultUserShell = pkgs.fish;
  security.sudo.execWheelOnly = true;
  nix.settings.trusted-users = [ "steelph0enix" ];

  security.pam.loginLimits = [
    {
      domain = "*";
      item = "memlock";
      value = "infinity";
    }
  ];
}
