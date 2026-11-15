{ settings, ... }:
let
  sites = [
    {
      port = settings.coveragePort;
      dir = "/srv/coverage";
    }
    {
      port = settings.docsPort;
      dir = "/srv/docs";
    }
  ];
in
{
  systemd.tmpfiles.rules = map (site: "d ${site.dir} 0755 ${settings.userName} users -") sites;

  services.caddy.virtualHosts = builtins.listToAttrs (
    map (site: {
      name = ":${toString site.port}";
      value.extraConfig = ''
        root * ${site.dir}
        file_server browse
      '';
    }) sites
  );
}
