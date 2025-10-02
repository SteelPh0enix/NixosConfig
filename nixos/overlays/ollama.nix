{ overridePkgs, ... }:
(self: super: {
  ollama = super.ollama-rocm.override {
    rocmPackages = overridePkgs.rocmPackages;
    rocmGpuTargets = [ "gfx1151" ];
    acceleration = "rocm";
  };
})
