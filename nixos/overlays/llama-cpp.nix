{ overridePkgs, ... }:
(self: super: {
  llama-cpp = overridePkgs.llamaPackages.llama-cpp.override {
    llamaVersion = "1.2.3";
    useRocm = false;
    useMpi = true;
    useVulkan = true;
    useBlas = true;
    enableUma = true;
  };
})
