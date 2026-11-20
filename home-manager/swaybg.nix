{
  pkgs,
  settings,
  ...
}:
let
  # One random still per panel. Everything in ~/Pictures/Wallpapers is an exact 2560x1440 canvas
  # (stills blur-padded from /mnt/HDD/nebulas), so stretch covers the panel: no bars, no crop,
  # no distortion.
  wallpapersDir = "/home/${settings.userName}/Pictures/Wallpapers";

  # swaybg has no random pick of its own, so a fresh image per panel is chosen here.
  pickRandom = pkgs.writeShellScript "swaybg-random" ''
    pick() {
      ${pkgs.findutils}/bin/find "${wallpapersDir}" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) |
      ${pkgs.coreutils}/bin/shuf -n1
    }
    exec ${pkgs.swaybg}/bin/swaybg \
      -o DP-1 -i "$(pick)" -m stretch \
      -o DP-2 -i "$(pick)" -m stretch
  '';
in
{
  home.packages = [ pkgs.swaybg ];

  # swaybg draws one still and idles, so the rotation is the unit restarting itself every 15 min:
  # RuntimeMaxSec stops it, Restart brings it back with a fresh random pick per panel.
  systemd.user.services.swaybg = {
    Unit = {
      Description = "swaybg wallpaper";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pickRandom}";
      RuntimeMaxSec = 15 * 60;
      Restart = "always";
      RestartSec = 5;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
