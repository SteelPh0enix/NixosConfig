{ overridePkgs, ... }:
(self: super: {
  llama-cpp = overridePkgs.llamaPackages.llama-cpp.override {
    llamaVersion = "4.2.0";
    useRocm = false;
    useVulkan = true;
    useMpi = true;
  };
})
