final: prev: {
  # Built from the local checkout (flake input `llama-cpp`), see the `llama-cpp-update`
  # script. ROCm stays off; the GPU is offloaded through Vulkan.
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
          # (NIX_ENFORCE_NO_NATIVE) off and lets one derivation hash hide different binaries, so
          # a closure copied to another CPU can SIGILL. These flags pin the same instruction set
          # (Zen 3 = x86-64-v3: AVX2/FMA/F16C/BMI2) plus this CPU's scheduling - reproducible and
          # shareable. Upstream already builds the ggml-cpu kernels with `-mavx2` and runtime
          # dispatch (GGML_NATIVE=OFF); this additionally tunes everything else.
          NIX_CFLAGS_COMPILE = "-march=x86-64-v3 -mtune=znver3";
        }
      );
}
