final: prev:
let
  # LTO archives hold only GCC IR, so they must be indexed with the LTO plugin; the cc-wrapper
  # ships plain `ar`, which cannot (link then fails with undefined references).
  ltoAr = "${prev.stdenv.cc.cc}/bin/gcc-ar";
  ltoRanlib = "${prev.stdenv.cc.cc}/bin/gcc-ranlib";

  # Built from the local checkout (flake input `llama-cpp`), see the `llama-cpp-update` script.
  # Vulkan is what this GPU speaks; ROCm stays off, that stack runs from its own container
  # (nixos/services/llm-router-rocm).
  llama-cpp-with =
    {
      useCuda ? false,
      useMetalKit ? false,
      useRocm ? false,
      useVulkan ? true,
    }:
    (prev.llamaPackages.llama-cpp.override { inherit useCuda useMetalKit useRocm useVulkan; })
    .overrideAttrs
      (
        _finalAttrs: prevAttrs: {
          # Add 'cacert' to the build inputs so SSL certificates are available
          nativeBuildInputs = (prevAttrs.nativeBuildInputs or [ ]) ++ [ prev.cacert ];

          # Tell CMake/Curl where to find the certificates
          SSL_CERT_FILE = "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";

          # Zen 5 ISA, stated explicitly (`-march=native` needs the cc-wrapper purity guard off,
          # which lets one derivation hash hide two binaries). x86-64-v4 is not enough: it leaves
          # out AVX512-VNNI/VBMI/BF16, and ggml gates its quantized vec-dot and repacked-GEMM
          # kernels on exactly those macros.
          NIX_CFLAGS_COMPILE = "-march=znver5 -mtune=znver5";

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

  # ffmpeg-full (so mpv too) builds whisper.cpp against the system llama-cpp, and overrides it
  # with nixpkgs' names - cudaSupport, rocmSupport, vulkanSupport - which upstream's
  # package.nix, calling them useCuda/useRocm/useVulkan, rejects. Mapping the two sets keeps
  # whisper on our Vulkan-enabled llama.cpp.
  whisper-cpp = prev.whisper-cpp.override {
    vulkanSupport = true;
    llama-cpp = prev.lib.makeOverridable (
      {
        cudaSupport ? false,
        rocmSupport ? false,
        vulkanSupport ? true,
        metalSupport ? false,
        ...
      }:
      llama-cpp-with {
        useCuda = cudaSupport;
        useRocm = rocmSupport;
        useVulkan = vulkanSupport;
        useMetalKit = metalSupport;
      }
    ) { };
  };
}
