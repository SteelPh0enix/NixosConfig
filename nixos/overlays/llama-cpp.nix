{ llamaPkgs, ... }:
(self: super: {
  llama-cpp = llamaPkgs.llamaPackages.llama-cpp.override {
    llamaVersion = "1.2.3";
    useRocm = false;
    useMpi = true;
    useVulkan = true;
    useBlas = true;
    enableUma = true;
  };
})
