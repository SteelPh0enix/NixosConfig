_final: prev:
let
  # LTO archives hold only GCC IR: index them with the LTO plugin, not the cc-wrapper's plain `ar`.
  ltoAr = "${prev.stdenv.cc.cc}/bin/gcc-ar";
  ltoRanlib = "${prev.stdenv.cc.cc}/bin/gcc-ranlib";

  # Built from the local checkout (flake input `llama-cpp`); Vulkan is the only backend we build.
  llama-cpp-with =
    {
      useCuda ? false,
      useMetalKit ? false,
      useRocm ? false,
      useVulkan ? true,
    }:
    # No WebUI: its npm build dies on a `file:` symlink npm 11 never unpacks (nixpkgs#576406).
    (prev.llamaPackages.llama-cpp.override {
      inherit
        useCuda
        useMetalKit
        useRocm
        useVulkan
        ;
      useWebUi = false;
    }).overrideAttrs
      (
        _finalAttrs: prevAttrs: {
          # `useWebUi` only gates postPatch and the cmake flag; a leftover `webui` keeps npm in.
          webui = null;

          nativeBuildInputs = (prevAttrs.nativeBuildInputs or [ ]) ++ [ prev.cacert ];

          SSL_CERT_FILE = "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";

          # Zen 3 ISA stated explicitly: `-march=native` needs the purity guard off, and then one
          # derivation hash can hide two binaries.
          NIX_CFLAGS_COMPILE = "-march=znver3 -mtune=znver3";

          # Pinned: an upstream default flip would silently pick a slower build type.
          cmakeBuildType = "Release";

          # ggml's own GGML_LTO only reaches the ggml/ targets, leaving the rest unoptimized.
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

  # whisper.cpp forwards cuda/rocm/vulkan support to llama-cpp, and those default to the nixpkgs
  # config's `rocmSupport = true`, so it would build a hipcc llama.cpp on top of Vulkan.
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
          # talk-llama's cmake accepts only llama.cpp 0.6.x, and the 1.0.0 bump changed the version
          # number alone.
          postPatch = (prevAttrs.postPatch or "") + ''
            substituteInPlace examples/talk-llama/CMakeLists.txt \
              --replace-fail 'find_package(llama 0.6.0 REQUIRED)' 'find_package(llama REQUIRED)'
          '';
        }
      );
}
