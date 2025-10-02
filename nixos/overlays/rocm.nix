{ overridePkgs, ... }:
(self: super: {
  rocmPackages = super.rocmPackages // rec {
    clr =
      (super.rocmPackages.clr.override {
        localGpuTargets = [ "gfx1151" ];
      }).overrideAttrs
        (oldAttrs: {
          passthru = oldAttrs.passthru // {
            gpuTargets = oldAttrs.passthru.gpuTargets ++ [ "gfx1151" ];
          };
        });

    rocminfo = (
      super.rocmPackages.rocminfo.override {
        clr = clr;
      }
    );

    rocblas = (
      super.rocmPackages.rocblas.override {
        clr = clr;
      }
    );

    rocsparse = (
      super.rocmPackages.rocsparse.override {
        clr = clr;
      }
    );

    rocsolver = (
      super.rocmPackages.rocsolver.override {
        clr = clr;
      }
    );
  };
})
