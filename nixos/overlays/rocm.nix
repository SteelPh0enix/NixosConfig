final: prev: {
  rocmPackages = prev.rocmPackages // rec {
    clr =
      (prev.rocmPackages.clr.override {
        localGpuTargets = [ "gfx1151" ];
      }).overrideAttrs
        (oldAttrs: {
          passthru = oldAttrs.passthru // {
            gpuTargets = oldAttrs.passthru.gpuTargets ++ [ "gfx1151" ];
          };
        });

    rocminfo = (
      prev.rocmPackages.rocminfo.override {
        clr = clr;
      }
    );

    rocblas = (
      prev.rocmPackages.rocblas.override {
        clr = clr;
      }
    );

    rocsparse = (
      prev.rocmPackages.rocsparse.override {
        clr = clr;
      }
    );

    rocsolver = (
      prev.rocmPackages.rocsolver.override {
        clr = clr;
      }
    );
  };
}
