{ overridePkgs, ... }:
(self: super: {
  llama-cpp =
    (overridePkgs.llamaPackages.llama-cpp.override {
      llamaVersion = "4.2.0";
      useRocm = false;
      useVulkan = true;
      useMpi = true;
    }).overrideAttrs
      (oldAttrs: {
        # This instructs Nix to run the build outside the sandbox,
        # allowing access to the network to download the models.
        # Requires 'sandbox = relaxed' or 'false' in /etc/nix/nix.conf
        __noChroot = true;

        # Add 'cacert' to the build inputs so SSL certificates are available
        nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ super.cacert ];

        # Tell CMake/Curl where to find the certificates
        SSL_CERT_FILE = "${super.cacert}/etc/ssl/certs/ca-bundle.crt";
      });
})
