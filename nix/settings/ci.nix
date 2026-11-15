{
  # A job container reaches only the bridge gateway, where ci-gateway hands out the few
  # services a build asks for.
  ciNetwork = "ci";
  ciBridge = "br-ci0"; # docker names the bridge after this opt (15 chars at most)
  ciSubnet = "172.42.0.0/24";
  ciGateway = "172.42.0.1";
  ciRunnerImage = "localhost/ci-runner:1";
  ciCachePort = 19777;
  ciLlmPort = 19778;
  ciProxyPort = 19779;
}
