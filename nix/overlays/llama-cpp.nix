_final: prev:
let
  # LTO archives hold only GCC IR, so they must be indexed with the LTO plugin; the cc-wrapper
  # ships plain `ar`, which cannot (link then fails with undefined references).
  ltoAr = "${prev.stdenv.cc.cc}/bin/gcc-ar";
  ltoRanlib = "${prev.stdenv.cc.cc}/bin/gcc-ranlib";

  # Built from the local checkout (flake input `llama-cpp`), see the `llama-cpp-update` script.
  # Vulkan is what this GPU speaks, so it is the only backend we build (nixos/services/llama-server-vulkan).
  llama-cpp-with =
    {
      useCuda ? false,
      useMetalKit ? false,
      useRocm ? false,
      useVulkan ? true,
    }:
    # No WebUI: its `npm run build` dies on `llama-brand`, which importNpmLock turns into a `file:`
    # symlink npm 11 never unpacks, so the favicons the PWA generator wants are missing. Temporary:
    # the server then serves no chat page (server-http.cpp skips the asset routes).
    (prev.llamaPackages.llama-cpp.override {
      inherit useCuda useMetalKit useRocm useVulkan;
      useWebUi = false;
    })
    .overrideAttrs
      (
        _finalAttrs: prevAttrs: {
          # Still unconditional upstream: `useWebUi` only gates postPatch and the cmake flag, and a
          # leftover `webui` attribute would keep npm in the build graph.
          webui = null;

          # Add 'cacert' to the build inputs so SSL certificates are available
          nativeBuildInputs = (prevAttrs.nativeBuildInputs or [ ]) ++ [ prev.cacert ];

          # Tell CMake/Curl where to find the certificates
          SSL_CERT_FILE = "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";

          # Zen 3 ISA, stated explicitly (`-march=native` needs the cc-wrapper purity guard off,
          # which lets one derivation hash hide two binaries).
          NIX_CFLAGS_COMPILE = "-march=znver3 -mtune=znver3";

          # Release is what the cmake hook picks by default (-O3 -DNDEBUG); pinned so an
          # upstream default flip cannot silently drop us to a slower build type.
          cmakeBuildType = "Release";

          # Whole-build IPO. ggml's own GGML_LTO only reaches the ggml/ targets, leaving
          # libllama, common and server unoptimized.
          cmakeFlags = (prevAttrs.cmakeFlags or [ ]) ++ [
            (prev.lib.cmakeBool "CMAKE_INTERPROCEDURAL_OPTIMIZATION" true)
            (prev.lib.cmakeFeature "CMAKE_C_COMPILER_AR" ltoAr)
            (prev.lib.cmakeFeature "CMAKE_CXX_COMPILER_AR" ltoAr)
            (prev.lib.cmakeFeature "CMAKE_C_COMPILER_RANLIB" ltoRanlib)
            (prev.lib.cmakeFeature "CMAKE_CXX_COMPILER_RANLIB" ltoRanlib)
          ];
        }
      );
in
{
  llama-cpp = llama-cpp-with { };

  # ffmpeg-full (so mpv too) builds whisper.cpp, which forwards cudaSupport/rocmSupport/vulkanSupport
  # to llama-cpp. Those default to the nixpkgs config, and `rocmSupport = true` here (for other
  # packages), so whisper was pulling a hipcc GGML_HIP llama.cpp with every ROCm GPU target on top
  # of Vulkan. llama.cpp is reached under upstream's names - useCuda/useRocm/useVulkan - which is
  # what this mapping is for; the flags are pinned so whisper always gets exactly `llama-cpp`
  # above, and ROCm stays available to the rest of the package set.
  whisper-cpp =
    (prev.whisper-cpp.override {
      cudaSupport = false;
      rocmSupport = false;
      vulkanSupport = true;
      llama-cpp = prev.lib.makeOverridable (
        {
          metalSupport ? false,
          ...
        }:
        llama-cpp-with { useMetalKit = metalSupport; }
      ) { };
    }).overrideAttrs
      (
        _finalAttrs: prevAttrs: {
          # talk-llama's cmake asks for llama.cpp 0.6.0 and accepts only that major version, which
          # our 1.0.0 checkout fails even though the bump touched nothing but the version number.
          postPatch = (prevAttrs.postPatch or "") + ''
            substituteInPlace examples/talk-llama/CMakeLists.txt \
              --replace-fail 'find_package(llama 0.6.0 REQUIRED)' 'find_package(llama REQUIRED)'
          '';
        }
      );
}
