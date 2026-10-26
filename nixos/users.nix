{
  pkgs,
  settings,
  ...
}:
{
  # Only groups no NixOS module creates (normal users already get `users` as their primary group).
  users.groups.samba = { };

  # Shared by the GPU engines: gufo and llama-server-vulkan both run as this account.
  users.groups.llm = { };

  users.users = {
    ${settings.userName} = {
      isNormalUser = true;
      extraGroups = [
        "docker"
        "networkmanager"
        "pcap"
        "render"
        "samba"
        "systemd-journal"
        "vboxusers"
        "video"
        "wheel"
        "wireshark"
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID7HEYiuWVQP3BcNDibe5cwVuL081u1Noos4OAuyWVBb FrameworkPC SSH"
        # Deploy key used by Forgejo CI to publish coverage reports to
        # /srv/coverage and API docs to /srv/docs
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIMBBk8Y/FcUNsIemBzYJb7TiBMYpnT1ik/H9+obvnxR forgejo-localmachine"
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

    # The GPU engines' account. Only one engine loads at a time, so the units share it. It also owns
    # the rootless Docker daemon the ROCm container runs on (nixos/services/llama-server-rocm), which
    # is why the uid is pinned: the unit names /run/user/<uid>/docker.sock and user@<uid>.service.
    llm = {
      group = "llm";
      isSystemUser = true;
      uid = 978;
      home = "/var/lib/llm";
      createHome = true;
      # Rootless Docker starts with the user manager, not with a login session.
      linger = true;
      subUidRanges = [
        {
          startUid = 200000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 200000;
          count = 65536;
        }
      ];
    };

    qbittorrent = {
      isNormalUser = false;
      group = "users";
    };
  };

  # Primary shell; `programs.fish.enable` (nixos/packages) is what puts it in /etc/shells.
  users.defaultUserShell = pkgs.fish;

  security.sudo.execWheelOnly = true;

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
