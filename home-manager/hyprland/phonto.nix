{
  pkgs,
  settings,
  ...
}:
let
  phontoPkg = pkgs.phonto; # built by nix/overlays/phonto.nix
in
{
  home.packages = [ phontoPkg ];

  # One random clip per panel, from ~/Pictures/Wallpapers. Keep that directory at panel
  # resolution - HEVC stays cheap to decode, the originals live in ~/Pictures/originalWallpapers:
  #   ffmpeg -i in.mp4 -vf scale=2560:1440:flags=lanczos -c:v libx265 -preset slow -crf 23 \
  #     -tag:v hvc1 -colorspace bt709 -color_primaries bt709 -color_trc bt709 -an out.mp4
  xdg.configFile."phonto/config.toml".text = ''
    [[search_paths]]
    path = "/home/${settings.userName}/Pictures/Wallpapers"
    depth = 0

    [[display]]
    id = "DP-1"
    random = true

    [[display]]
    id = "DP-2"
    random = true
  '';

  # phonto loops the current clip forever and has no rotation timer, so the unit restarts itself
  # every 15 min: RuntimeMaxSec stops it, Restart brings it back with a fresh random pick.
  systemd.user.services.phonto = {
    Unit = {
      Description = "phonto video wallpaper";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${phontoPkg}/bin/phonto";
      RuntimeMaxSec = 15 * 60;
      Restart = "always";
      RestartSec = 5;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
