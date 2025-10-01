(self: super: {
  ollama-fpc = super.ollama-rocm.override {
    rocmGpuTargets = [ "gfx1151" ];
  };
})
