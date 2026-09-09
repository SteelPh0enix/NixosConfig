final: prev: {
  # Built from the local checkout (flake input `llama-cpp`), see `llama-cpp-update` in
  # home-manager/shell.nix. ROCm stays off here; the ROCm stack runs from its own container
  # (nixos/services/llm-router-rocm).
  llama-cpp =
    (prev.llamaPackages.llama-cpp.override {
      llamaVersion = "4.2.0";
      useVulkan = true;
      useRocm = false;
    }).overrideAttrs
      (
        _finalAttrs: prevAttrs: {
          # Add 'cacert' to the build inputs so SSL certificates are available
          nativeBuildInputs = (prevAttrs.nativeBuildInputs or [ ]) ++ [ prev.cacert ];

          # Tell CMake/Curl where to find the certificates
          SSL_CERT_FILE = "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";

          # CPU tuning without `-march=native`: that flag needs the cc-wrapper's purity guard
          # (NIX_ENFORCE_NO_NATIVE) off, which lets one derivation hash hide different binaries.
          # These pin this machine's ISA explicitly (Zen 5 = x86-64-v4: AVX-512F/BW/CD/DQ/VL).
          # Upstream already runtime-dispatches the ggml-cpu kernels (GGML_NATIVE=OFF); this
          # additionally tunes everything else.
          NIX_CFLAGS_COMPILE = "-march=x86-64-v4 -mtune=znver5";
        }
      );
}
