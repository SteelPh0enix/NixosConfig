# Static coverage reports, published by Forgejo CI (tar over SSH from the
# coverage job in SteelPh0enix/llama-server-api).
#
# Layout under /srv/coverage:
#   llama-server-api/<sha>/{html,lcov.info}
#   llama-server-api/latest -> llama-server-api/<newest sha>
#
# Browse at http://steelph0enix.framework:6970/
{ ... }:

{
  services.nginx.virtualHosts."6970" = {
    listen = [ { port = 6970; addr = "0.0.0.0"; } ];
    locations."/".extraConfig = ''
      root /srv/coverage;
      index index.html;
      autoindex on;
    '';
  };
}
