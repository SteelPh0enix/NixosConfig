# Static coverage reports, published by Forgejo CI (tar over SSH from the
# coverage job in SteelPh0enix/llama-server-api).
#
# Same scheme as the docs viewer: only the latest build is kept, each publish
# replaces the project's report in place (no per-sha history).
#
# Layout under /srv/coverage:
#   <project>/{html,lcov.info}
#
# Browse at http://steelph0enix.framework:6970/
_:

{
  # Publish target for the CI coverage job (steelph0enix writes via SSH deploy key)
  # (option moved from boot.tmpfiles to systemd.tmpfiles in current nixpkgs)
  systemd.tmpfiles.rules = [
    "d /srv/coverage 0755 steelph0enix users -"
  ];

  # A bare port as the site address serves plain HTTP on the LAN; `file_server browse` is
  # nginx's `autoindex`, and `index.html` stays the file server's default index.
  services.caddy.virtualHosts.":6970".extraConfig = ''
    root * /srv/coverage
    file_server browse
  '';
}
