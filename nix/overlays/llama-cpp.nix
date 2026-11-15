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
    (prev.llamaPackages.llama-cpp.override {
      inherit
        useCuda
        useMetalKit
        useRocm
        useVulkan
        ;
    }).overrideAttrs
      (
        _finalAttrs: prevAttrs: {
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
          # talk-llama accepts only llama.cpp 0.6.x, and our 1.0.0 checkout fails that check.
          postPatch = (prevAttrs.postPatch or "") + ''
            substituteInPlace examples/talk-llama/CMakeLists.txt \
              --replace-fail 'find_package(llama 0.6.0 REQUIRED)' 'find_package(llama REQUIRED)'
          '';
        }
      );
}
