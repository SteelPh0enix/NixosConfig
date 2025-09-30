{ pkgs, ... }:
{
  services.samba = {
    enable = true;
    package = pkgs.sambaFull;
    openFirewall = true;
    nsswins = true;
    usershares.enable = true;
    winbindd.enable = true;
    nmbd.enable = true;
    smbd.enable = true;
    settings = {
      global = {
        security = "user";
        workgroup = "WORKGROUP";
        "server string" = "RX-78-FPC";
        "netbios name" = "RX-78-FPC";
        "hosts allow" = "192.168.0. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };

      "LLMs" = {
        path = "/home/steelph0enix/LLMs";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "steelph0enix";
        "force group" = "users";
      };

      "Shared" = {
        path = "/home/steelph0enix/Shared";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "steelph0enix";
        "force group" = "users";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
    interface = "enp191s0";
    discovery = true;
    workgroup = "WORKGROUP";
  };
}
