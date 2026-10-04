final: _:
let
  version = "14.0.3";

  # Flashpoint's "main version" for Linux: the launcher (Launcher/), the content index (Data/, with
  # the 450 MB flashpoint.sqlite that makes the game list), the support applications (FPSoftware/),
  # the legacy web root (Legacy/) and FP's own bundled Libraries + Wine runtime.
  # https://flashpointarchive.org/datahub/Linux_Support
  bundle = final.fetchurl {
    url = "https://download.flashpointarchive.org/upload/fp14.0.3_lin_20251201.7z";
    hash = "sha256-85OpjFw14imnRMECsMtTJwsbTxs+vUDWBPmDI0RKSx8=";
  };
in
{
  # The bundle is unpacked into ~/.local/share/flashpoint on first run rather than run from the
  # store: the launcher wants a Flashpoint root it can write to (launcher.log, game records, the
  # downloaded data packs, the Wine prefix).
  flashpoint = final.buildFHSEnv {
    pname = "flashpoint";
    inherit version;
    executableName = "flashpoint";

    # Dependency list from the Linux Support page: X11 + XWayland, GTK2/3, NSS, PulseAudio/PipeWire,
    # PHP, 7-Zip and Wine. 32-bit Windows content runs through the WoW64 wine, so the docs' extra
    # i686 libXcomposite/libpulse packages are not needed (that wine build pulls in no 32-bit Unix
    # libraries at all).
    targetPkgs =
      pkgs: with pkgs; [
        alsa-lib
        at-spi2-atk
        at-spi2-core
        cairo
        cups
        dbus
        expat
        glib
        gtk2 # native Flash projector
        gtk3
        libdrm
        libgbm
        libGL
        libx11
        libxcomposite
        libxcursor
        libxdamage
        libxcb
        libxext
        libxfixes
        libxi
        libxkbcommon
        libxrandr
        libxt # native Flash projector
        nss
        nspr
        p7zip # unpacks the bundle, then extracts the game data packs
        pango
        php # the Legacy router.php
        pipewire
        pulseaudio
        udev
        vulkan-loader # the ICDs come from /run/opengl-driver/share, already on XDG_DATA_DIRS
        wayland # Wine's Wayland driver and Electron's ozone backend dlopen libwayland-client/-cursor
        wineWow64Packages.stagingFull
        xdg-utils # xdg-open, what the HTML5 platform hands the url to
      ];

    # Electron's chrome-sandbox needs to be setuid-root (the docs have you chown it in the install
    # dir); nothing declared here does that, so it runs with --no-sandbox.
    runScript = final.writeShellScript "flashpoint-run" ''
      set -eu
      root="''${XDG_DATA_HOME:-$HOME/.local/share}/flashpoint"
      # Excluded because this container replaces them: the bundled Libraries (Debian's system libs)
      # and FP's Wine runtime (nixpkgs' wine below, in a prefix of its own).
      if [ "$(cat "$root/.bundle" 2>/dev/null)" != "${bundle}" ]; then
        echo "unpacking the Flashpoint bundle into $root (~2.2 GB, first run only)" >&2
        mkdir -p "$root"
        # A -wal left over from the launcher's own empty database would be replayed onto the
        # extracted one.
        rm -f "$root/Data/flashpoint.sqlite-wal" "$root/Data/flashpoint.sqlite-shm"
        7z x -y -bd '-x!Libraries/*' '-x!FPSoftware/Wine/*' -o"$root" ${bundle}
        printf '%s' "${bundle}" >"$root/.bundle"
      fi
      # The GPU driver only lives in the host's /run/opengl-driver, which ld.so does not search.
      export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      export WINEPREFIX="$root/FPSoftware/Wine"
      mkdir -p "$WINEPREFIX"
      # The launcher takes its root from the parent of the cwd (it opens ../Data/services.json), so
      # it runs from Launcher/ like the bundle's own start-flashpoint.sh does. No ozone flags: the
      # Electron 19 build here does not know them, only the later ones upstream's script assumes.
      cd "$root/Launcher"
      exec ./flashpoint-launcher --no-sandbox "$@"
    '';

    meta = {
      description = "Browser and launcher for the Flashpoint Archive";
      homepage = "https://flashpointarchive.org";
      license = with final.lib.licenses; [ gpl3Only ];
      mainProgram = "flashpoint";
      platforms = [ "x86_64-linux" ];
    };
  };
}
