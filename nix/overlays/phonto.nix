inputs: final: _: {
  # GPU-decoded video wallpaper daemon, used by home-manager/hyprland/phonto.nix.
  #
  # Built here rather than taking `inputs.phonto.packages`: that flake pins a nixpkgs whose crate
  # fetcher still uses crates.io's retired `api/v1/.../download` endpoint, which now answers 403
  # (`static.crates.io/crates/...` works). Upstream's dependency list also lacks the VA-API
  # decoder; on GStreamer >= 1.28 that plugin lives in gst-plugins-bad, which is listed below.
  phonto = final.rustPlatform.buildRustPackage {
    pname = "phonto";
    version = (final.lib.importTOML "${inputs.phonto}/Cargo.toml").package.version;

    src = inputs.phonto;
    cargoLock.lockFile = "${inputs.phonto}/Cargo.lock";

    nativeBuildInputs = with final; [
      pkg-config
      wrapGAppsHook4
    ];

    buildInputs =
      with final;
      [
        libGL
        mesa
        wayland
      ]
      ++ (with final.gst_all_1; [
        gstreamer
        gst-libav
        gst-plugins-bad
        gst-plugins-base
        gst-plugins-good
        gst-plugins-ugly # `bad` carries the `va` VA-API decoder (GStreamer >= 1.28)
      ]);

    meta = {
      description = "GPU-accelerated video wallpaper for Wayland compositors";
      homepage = "https://github.com/museslabs/phonto";
      license = final.lib.licenses.gpl3Plus;
      platforms = final.lib.platforms.linux;
      mainProgram = "phonto";
    };
  };
}
