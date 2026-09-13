final: prev: {
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
        }
      );
}
