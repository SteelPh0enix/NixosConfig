rec {
  # Models kept resident at once (20 GB of VRAM here).
  llamaModelsMax = 1;

  # Which engine owns the router port: "vulkan" (the llama-cpp package) or "rocm" (the gfx1100
  # toolbox container, on hold after it kept crashing the router). Both units stay configured.
  llamaBackend = "vulkan";
  llamaRouterService = "llama-server-${llamaBackend}";
  llamaRocmImage = "llama-rocm-10.1-gfx1100:latest";
}
