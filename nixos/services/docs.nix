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
_:

{
  # Publish target for the CI docs job (steelph0enix writes via SSH deploy key)
  # (option moved from boot.tmpfiles to systemd.tmpfiles in current nixpkgs)
  systemd.tmpfiles.rules = [
    "d /srv/docs 0755 steelph0enix users -"
  ];

  # A bare port as the site address serves plain HTTP on the LAN; `file_server browse` is
  # nginx's `autoindex`, and `index.html` stays the file server's default index.
  services.caddy.virtualHosts.":6971".extraConfig = ''
    root * /srv/docs
    file_server browse
  '';
}
