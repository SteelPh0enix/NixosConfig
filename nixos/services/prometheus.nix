{ pkgs, ... }:

{
  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    listenPort = 9090;
    globalConfig.scrape_interval = "15s";
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