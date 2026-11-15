{ repoPath }:
rec {
  # Weights and preset files. The inference units run as `llm`, and /home is 0700, so
  # nothing below it can be reached from the store or the human's home.
  llamaModelsPath = "/home/LLMs";
  llamaPresetsPath = "${llamaModelsPath}/llama-server.ini";
  llamaRocmPresetsPath = "${llamaModelsPath}/llama-server-rocm.ini";
  llamaRocmToolboxesPath = "${llamaModelsPath}/amd-strix-halo-toolboxes";

  nasPath = "/mnt/NAS";
  nas2Path = "/mnt/NAS2";

  llmApiKeyFile = "${repoPath}/secrets/llama-strix-api-key";
  ciRunnerTokenFile = "${repoPath}/secrets/ci-runner-token";
}
