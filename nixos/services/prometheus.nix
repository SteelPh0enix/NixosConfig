{
  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    listenPort = 9090;
    scrapeInterval = "15s";
    scrapeTimeout = "10s";
    externalLabels = {
      prometheus = "nixos";
      monitor = "codelab";
    };
    rules = null;
    alertmanagerConfigs = [];
    scrapeConfigs = [
      {
        job_name = "llm-router";
        static_configs = [
          {
            targets = [ "localhost:51536" ];
          }
        ];
        metrics_path = "/metrics";
        scrape_interval = "15s";
      }
    ];
  };
  firewall.allowedTCPPorts = [ 9090 ];
}
