# Static API documentation (rustdoc HTML), published by Forgejo CI (tar over
# SSH from the docs job in SteelPh0enix/llama-server-api).
#
# Same viewer as the coverage reports, but without per-build history: each
# publish replaces the project's docs in place, so only the latest build is
# ever served.
#
# Layout under /srv/docs:
#   <project>/  (rustdoc site: index.html, <crate>/, ...)
#
# Browse at http://steelph0enix.framework:6971/
{ ... }:

{
  # Publish target for the CI docs job (steelph0enix writes via SSH deploy key)
  # (option moved from boot.tmpfiles to systemd.tmpfiles in current nixpkgs)
  systemd.tmpfiles.rules = [
    "d /srv/docs 0755 steelph0enix users -"
  ];

  services.nginx.virtualHosts."6971" = {
    listen = [ { port = 6971; addr = "0.0.0.0"; } ];
    locations."/".extraConfig = ''
      root /srv/docs;
      index index.html;
      autoindex on;
    '';
  };
}
