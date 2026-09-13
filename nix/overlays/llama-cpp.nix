final: prev:
let
  # LTO archives hold only GCC IR, so they must be indexed with the LTO plugin; the cc-wrapper
  # ships plain `ar`, which cannot (link then fails with undefined references).
  ltoAr = "${prev.stdenv.cc.cc}/bin/gcc-ar";
  ltoRanlib = "${prev.stdenv.cc.cc}/bin/gcc-ranlib";
in
{
  # Built from the local checkout (flake input `llama-cpp`), see the `llama-cpp-update`
  # script. ROCm stays off here; the ROCm stack runs from its own container
  # (nixos/services/llm-router-rocm).
  llama-cpp =
    (prev.llamaPackages.llama-cpp.override {
      useVulkan = true;
      useRocm = false;
    }).overrideAttrs
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
}
