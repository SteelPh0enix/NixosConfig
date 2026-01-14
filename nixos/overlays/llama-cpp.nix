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
      });
})
