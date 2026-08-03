final: prev: {
  llama-cpp =
    (prev.llamaPackages.llama-cpp.override {
      llamaVersion = "4.2.0";
      useRocm = true;
      useVulkan = false;
      useMpi = true;
    }).overrideAttrs
      (oldAttrs: {
        # This instructs Nix to run the build outside the sandbox,
        # allowing access to the network to download the models.
        # Requires 'sandbox = relaxed' or 'false' in /etc/nix/nix.conf
        # __noChroot = true;

        # Add 'cacert' to the build inputs so SSL certificates are available
        nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.cacert ];

        # Tell CMake/Curl where to find the certificates
        SSL_CERT_FILE = "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";

        # Allow -march=native. The gcc wrapper strips this by default (NIX_ENFORCE_NO_NATIVE=1)
        # because it's impure — but for llama.cpp we actually want it, since the build runs on
        # our own CPU and we want full AVX-512 / AMX feature detection at compile time.
        NIX_ENFORCE_NO_NATIVE = false;

        # Enable GGML native CPU optimizations (-march=native) so ggml-cpu picks up
        # all CPU features (AVX-512, AMX, AVX-VNNI, etc.) automatically.
        cmakeFlags = builtins.map (flag:
          if builtins.match ".*GGML_NATIVE.*" flag != null
          then "-DGGML_NATIVE:BOOL=ON"
          else flag
        ) oldAttrs.cmakeFlags;
      });
}
