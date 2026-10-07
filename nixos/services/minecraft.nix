# Create+ (Minecraft 1.19.2 / Forge 43.5.1). The `services.minecraft-forge-server` module,
# the launcher package and the server pack all come from the `mcserver` input (a working
# checkout outside this repo). The pack is generated there by `scripts/build-pack.sh`,
# which has to be followed by `nix flake update mcserver`.
#
# Unlike jellyfin/qbittorrent this service has a private group: nothing under
# /var/lib/minecraft/createplus (world, configs, logs) is readable by other accounts.
# Use stateDirectoryMode = "0750" and join that group if you want direct access.
{ pkgs, inputs, ... }:
let
  mcserver = inputs.mcserver;
  createplus = import (mcserver + /packs/createplus/pack.nix) { };
in
{
  imports = [ (mcserver + /modules/minecraft-server.nix) ];

  services.minecraft-forge-server.instances.createplus = {
    enable = false;
    package = pkgs.callPackage (mcserver + /packages/minecraft-server) { pack = createplus; };

    port = 25565;
    openFirewall = true;
    motd = "Create+ ${createplus.version}";

    # 16G heap plus a few G of metaspace/native for 220 mods. MemoryHigh throttles rather
    # than OOM-kills, so jellyfin/forgejo keep their share even if the server leaks.
    memory = "16G";
    unitConfig.MemoryHigh = "24G";

    viewDistance = 24;
    simulationDistance = 24; # contraptions beyond view-distance stall on the 60ms tick budget
    maxPlayers = 4;
    pvp = true;
    allowFlight = true; # jetpacks, elytra
    gamemode = "survival";
    difficulty = "hard";
    onlineMode = false;

    voiceChat = {
      enable = true;
      openFirewall = true; # UDP 24454; forward it on the router for players outside the LAN
    };

    # RCON needs a root-owned secret outside the store, e.g.
    #   sudo install -m 600 -o root -g minecraft-createplus /dev/null /etc/minecraft-rcon-password
    # rcon = { enable = true; passwordFile = "/etc/minecraft-rcon-password"; };
    rcon.enable = false;
  };
}
