rec {
  lanPrefix = "192.168.0.";
  lanIp = "${lanPrefix}185";
  lanSubnet = "${lanPrefix}0/24";

  searchDomain = "search.framework";
  forgejoDomain = "steelph0enix.framework";
  publicDomain = "steelph0enix.dev";
  clankerHost = "clanker.${publicDomain}";
  searchHost = "search.${publicDomain}";

  workgroup = "WORKGROUP";
  enableRdp = false;

  # Services bind every interface; the firewall decides who gets in.
  llmHost = "0.0.0.0";

  # Host-facing ports chosen by this config. Standard ports (53, 139, 445) and
  # module-fixed ports (Jellyfin 8096/8920, wsdd 5357/3702) stay with their modules.
  llmPort = 51536;
  llamaLogsPort = 51580;
  # Loopback-only hop from gufo-auth to gufo; never opened in the firewall.
  gufoUpstreamPort = 51537;
  forgejoPort = 6969;
  sshPort = 22137;
  adguardUiPort = 8123;
  searxngPort = 7777;
  coveragePort = 6970;
  docsPort = 6971;
  qbittorrentWebPort = 8888;
  jackettPort = 8889;
  flaresolverrPort = 8890;
  xrdpPort = 3389;
  tailscalePort = 41641;
}
