(self: super: {
  python312Packages = super.python312Packages // {
    torch = (
      super.python312Packages.torch.override {
        rocmSupport = true;
        gpuTargets = [ "gfx1151" ];
        MPISupport = true;
      }
    );
  };
})
