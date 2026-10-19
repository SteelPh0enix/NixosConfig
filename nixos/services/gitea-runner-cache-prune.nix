# The Forgejo runner's actions cache never expires on its own: forgejo-runner knows only where
# to put it, and every repository that caches something adds an entry - the mc-modpack nix store,
# esquie's cargo registry and nix store, the checkout git caches. Fourteen days is long enough for
# a cache to outlive a work cycle and short enough that the runner's disk stays reasonable; a miss
# only costs a download.
{ pkgs, ... }:
{
  systemd.services."gitea-runner-cache-prune" = {
    description = "Prune the Forgejo runner's actions cache";
    path = with pkgs; [
      findutils
      coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      # One cache entry is a directory: the actions/cache blobs sit in the two-hex buckets, the
      # checkout action's git caches at the top level. The buckets themselves are left in place.
      ExecStart = [
        "find /var/lib/gitea-runner/framework/.cache/act -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf -- {} +"
        "find /var/lib/gitea-runner/framework/.cache/act -mindepth 2 -maxdepth 2 -type d -mtime +14 -exec rm -rf -- {} +"
      ];
    };
  };
}
