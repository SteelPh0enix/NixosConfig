_final: prev:
let
  # LTO archives need the LTO plugin's ar; the plain one cannot index them.
  ltoAr = "${prev.stdenv.cc.cc}/bin/gcc-ar";
  ltoRanlib = "${prev.stdenv.cc.cc}/bin/gcc-ranlib";

  # Built from the local `llama-cpp` checkout; Vulkan is the only backend this GPU uses.
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

          SSL_CERT_FILE = "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";

          # Zen 5 ISA explicitly, not `-march=native` (which would need the purity guard off).
          # x86-64-v4 lacks AVX512-VNNI/VBMI/BF16, which ggml's vec-dot and GEMM kernels gate on.
          NIX_CFLAGS_COMPILE = "-march=znver5 -mtune=znver5";

          # Pinned so an upstream default flip cannot drop to a slower build type.
          cmakeBuildType = "Release";

          # Whole-build IPO; GGML_LTO only reaches the ggml/ targets.
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

  # whisper.cpp forwards llama.cpp's cuda/rocm/vulkan flags from the package set; pin them so it
  # always gets the Vulkan build above, whatever the package-set default is.
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
          # talk-llama pins an exact llama.cpp version, and nixpkgs' own fetchpatch rewrites that
          # pin (currently 0.6.0 -> 1.0.0) before postPatch runs. The local checkout's version never
          # matches either, so strip the requirement instead of chasing the exact text.
          postPatch = (prevAttrs.postPatch or "") + ''
            sed -i 's/find_package(llama [0-9.]* REQUIRED)/find_package(llama REQUIRED)/' \
              examples/talk-llama/CMakeLists.txt
          '';
        }
      );
}
