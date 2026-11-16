rec {
  # Weights and presets. The units read them as unprivileged users and /home is 0700, so nothing
  # below a home directory.
  llamaModelsPath = "/mnt/NVMe/LLMs";
  llamaPresetsPath = "${llamaModelsPath}/llama-server.ini";
  llamaRocmPresetsPath = "${llamaModelsPath}/llama-server-rocm.ini";
}
