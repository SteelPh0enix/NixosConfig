{ llamaPkgs, ... }:
(self: super: {
  llama-cpp = llamaPkgs.llamaPackages.llama-cpp.override {
    llamaVersion = "1.2.3";
    buildAllCudaFaQuants = true;
    useMpi = true;
    rocmGpuTargets = "gfx1100";
  };
})
