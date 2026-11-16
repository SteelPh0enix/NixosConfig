rec {
  lanPrefix = "192.168.0.";
  frameworkIp = "${lanPrefix}185";
  pcIp = "${lanPrefix}150";

  frameworkHost = "steelph0enix.framework";
  pcHost = "steelph0enix.pc";
  searchDomain = "search.framework";

  # Host-facing ports; the firewall in nixos/networking.nix reads the same values.
  sshPort = 22137;
  searxngPort = 7777; # on the framework box
  llmHost = "0.0.0.0";
  llmPort = 51536;
  llamaLogsPort = 51580;
}
