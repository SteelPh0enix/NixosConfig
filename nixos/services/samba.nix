{ settings, ... }:
{
  services.samba = {
    enable = true;
    openFirewall = true;
    nsswins = true;
    usershares.enable = true;
    winbindd.enable = true;
    nmbd.enable = true;
    smbd.enable = true;
    settings = {
      global = {
        security = "user";
        inherit (settings) workgroup;
        "server string" = settings.hostId;
        "netbios name" = settings.hostId;
        "hosts allow" = "${settings.lanPrefix} 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };

      "LLMs" = {
        path = settings.llamaModelsPath;
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force group" = "users";
      };

      "HomeStorage" = {
        path = "/home/${settings.userName}/HomeStorage";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = settings.userName;
        "force group" = "users";
      };

      "NAS" = {
        path = settings.nasPath;
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force group" = "users";
      };

      "NAS2" = {
        path = settings.nas2Path;
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force group" = "users";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
    interface = "enp191s0";
    discovery = true;
    inherit (settings) workgroup;
  };
}
