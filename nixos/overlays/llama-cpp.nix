{ overridePkgs, ... }:
(self: super: {
  llama-cpp = overridePkgs.llamaPackages.llama-cpp.override {
    llamaVersion = "1.2.3";
    useRocm = false;
    useVulkan = true;
    enableUma = true;
  };
})
