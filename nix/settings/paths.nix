{ repoPath }:
rec {
  # Weights and preset files. The inference units run as `llm`, and /home is 0700, so
  # nothing below it can be reached from the store or the human's home.
  llamaModelsPath = "/home/LLMs";
  llamaPresetsPath = "${llamaModelsPath}/llama-server.ini";
  llamaRocmPresetsPath = "${llamaModelsPath}/llama-server-rocm.ini";
  llamaRocmToolboxesPath = "${llamaModelsPath}/amd-strix-halo-toolboxes";
  # Crucible's own home on the /home filesystem: since 0.38 its state folder needs a parent chain
  # only `llm` or root can change, and /home/LLMs is the human account's tree. The EXL3 pack it
  # serves lives here too, so no engine data stays with the human.
  crucibleHomePath = "/home/crucible";

  nasPath = "/mnt/NAS";
  nas2Path = "/mnt/NAS2";

  llmApiKeyFile = "${repoPath}/secrets/llama-strix-api-key";
  ciRunnerTokenFile = "${repoPath}/secrets/ci-runner-token";
}
