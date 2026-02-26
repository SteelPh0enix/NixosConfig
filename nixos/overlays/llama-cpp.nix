self: super: {
  llama-cpp =
    (super.llamaPackages.llama-cpp.override {
      llamaVersion = "4.2.0";
      useRocm = true;
      rocmGpuTargets = "gfx1100";
      useVulkan = false;
      useMpi = true;
    }).overrideAttrs
      (oldAttrs: {
        __noChroot = true;
        nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ super.cacert ];
        SSL_CERT_FILE = "${super.cacert}/etc/ssl/certs/ca-bundle.crt";
      });
}
