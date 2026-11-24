{ llamaModelsPath, crucibleHomePath }:
{
  # The engines that share llmPort; the units conflict, so only one is up at a time. Each engine
  # names the units it needs: gufo is unreachable without the caddy front door that owns llmPort.
  llmEngineUnits = {
    crucible = [ "crucible" ];
    gufo = [
      "gufo-auth"
      "gufo"
    ];
    llama-server-rocm = [ "llama-server-rocm" ];
    llama-server-vulkan = [ "llama-server-vulkan" ];
  };
  # The engine that boots with the system; the others start by hand.
  defaultLlmEngine = "crucible";

  # Models kept resident at once.
  llamaModelsMax = 1;

  # The Qwen3.8-Flash-Next target and its shared MTP sidecar, under llamaModelsPath so the
  # `llm` account can read them.
  gufoModelPath = "${llamaModelsPath}/models/qwen/3.8-Flash-Next/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf";
  gufoMtpPath = "${llamaModelsPath}/models/qwen/3.8-Flash-Next/UD-Q4_K_XL/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf";
  gufoServedModelName = "Qwen 3.8 Flash Next";
  gufoContext = 262144;
  # One session: the main agent and a subagent queue on the same slot.
  gufoSessions = 1;
  # Gufo sizes the continuation cache from free RAM once at startup and never re-checks it.
  gufoCacheRamBytes = 4 * 1024 * 1024 * 1024;
  # A stalled generation exits as device_lost so systemd restarts the engine.
  gufoStallTimeoutMs = 120000;

  llamaRocmImage = "llama-rocm-10.1-strix-llama";
  llamaRocmContainerPort = 44444;

  # Crucible's pack and the conversation cache it spills to, both under its own home (see
  # paths.nix) because the engine runs as `llm`.
  crucibleModelPath = "${crucibleHomePath}/models/qwen/3.8-Flash-Next/EXL3-4.05bpw_h6_ng6";
  crucibleStatePath = "${crucibleHomePath}/crucible-states";
  # The model id pi and omp pin for the framework endpoint.
  crucibleServedModelName = "Qwen 3.8 Flash Next";
}
