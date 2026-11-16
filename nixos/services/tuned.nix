{ lib, pkgs, ... }:
let
  # Noctalia's power slider speaks PPD names, which tuned-ppd maps onto these three profiles.
  selectableProfiles = {
    power-saver = "powersave";
    balanced = "desktop";
    performance = "throughput-performance";
  };

  # tuned re-enables HDA autosuspend on every activation, which buzzes the speakers for a few
  # seconds: shadowing the profiles in /etc/tuned/profiles wins over the shipped ones.
  noAudioPmProfile =
    name:
    pkgs.runCommand "tuned-${name}-no-audio-pm.conf" { } ''
      cat ${pkgs.tuned}/lib/tuned/profiles/${name}/tuned.conf > $out
      printf '\n[audio]\ntimeout=0\nreset_controller=false\n' >> $out
    '';
in
{
  services.tuned = {
    enable = true;
    ppdSupport = true;
    settings = {
      dynamic_tuning = true;
    };

    # `recommend` covers `tuned-adm auto`; the PPD slider sends `balanced`, hence -> `desktop`.
    recommend.desktop = { };
    ppdSettings = {
      main = {
        default = "balanced";
        battery_detection = false;
      };
      profiles = selectableProfiles;
      battery = { };
    };
  };

  environment.etc =
    lib.mapAttrs' (
      _: name: lib.nameValuePair "tuned/profiles/${name}/tuned.conf" { source = noAudioPmProfile name; }
    ) selectableProfiles
    // {
      "tuned/profiles/powersave/script.sh" = {
        source = "${pkgs.tuned}/lib/tuned/profiles/powersave/script.sh";
        mode = "0755";
      };
    };
}
