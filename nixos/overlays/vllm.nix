{ overridePkgs, ... }:
(self: super: {
  vllm = super.vllm.override {
    rocmSupport = true;
    python = overridePkgs.python312;
    torch = overridePkgs.python312Packages.torch;
    rocmPackages = overridePkgs.rocmPackages;
  };
})
