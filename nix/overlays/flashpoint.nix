final: _:
let
  version = "14.0.3";

  bundle = final.fetchurl {
    url = "https://download.flashpointarchive.org/upload/fp14.0.3_lin_20251201.7z";
    hash = "sha256-85OpjFw14imnRMECsMtTJwsbTxs+vUDWBPmDI0RKSx8=";
  };
in
{
  # Unpacked into ~/.local/share/flashpoint on first run: the launcher wants a root it can write
  # to (launcher.log, game records, data packs, the Wine prefix).
  flashpoint = final.buildFHSEnv {
    pname = "flashpoint";
    inherit version;
    executableName = "flashpoint";

    # Dependency list from the Linux Support page. 32-bit Windows content runs through the WoW64
    # wine, which pulls in no 32-bit Unix libraries, so the docs' i686 packages are not needed.
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
        libxt
        nss
        nspr
        p7zip
        pango
        php
        pipewire
        pulseaudio
        udev
        vulkan-loader
        wayland
        wineWow64Packages.stagingFull
        xdg-utils
      ];

    # Electron's chrome-sandbox needs to be setuid-root, which nothing declared here does, so it
    # runs with --no-sandbox.
    runScript = final.writeShellScript "flashpoint-run" ''
      set -eu
      root="''${XDG_DATA_HOME:-$HOME/.local/share}/flashpoint"
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
