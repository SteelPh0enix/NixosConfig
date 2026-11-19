inputs: final: _: {
  # Built here rather than taking `inputs.phonto.packages`: that flake pins a nixpkgs whose crate
  # fetcher uses crates.io's retired download endpoint (403 now). Its dependency list also lacks
  # the VA-API decoder, which lives in gst-plugins-bad on GStreamer >= 1.28 - listed below.
  phonto = final.rustPlatform.buildRustPackage {
    pname = "phonto";
    version = (final.lib.importTOML "${inputs.phonto}/Cargo.toml").package.version;

    src = inputs.phonto;
    cargoLock.lockFile = "${inputs.phonto}/Cargo.lock";

    # The random picker filters by a hardcoded extension allowlist, so still images never join
    # --rand/--display-rand even though GStreamer plays them fine when named explicitly. Adding
    # the extensions is what keeps the JPEGs in ~/Pictures/Wallpapers in the rotation.
    postPatch = ''
      substituteInPlace src/wallpaper.rs --replace-fail \
        '["mp4", "mkv", "webm", "avi", "mov", "gif", "ogv"]' \
        '["mp4", "mkv", "webm", "avi", "mov", "gif", "ogv", "jpg", "jpeg", "png"]'
    '';

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
