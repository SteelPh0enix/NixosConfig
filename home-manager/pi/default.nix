# The package comes from pi's own flake; everything else here is plain home-manager.
{
  lib,
  pkgs,
  pi,
  settings,
  ...
}:
let
  piPkg = pi.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  agentDir = ".pi/agent";

  piSettings = {
    defaultProvider = "framework";
    defaultModel = "Qwen 3.8 Flash Next";
    # xhigh where the preset has a rung for it; a model that maps xhigh to null sends no effort.
    defaultThinkingLevel = "xhigh";
    theme = "noctalia";
    transport = "auto";
    treeFilterMode = "default";
    enableSkillCommands = true;
    enableInstallTelemetry = false;
    defaultTools = [ "+codemode" ];
    # reserveTokens also caps the summary; keepRecentTokens survives unsummarized.
    compaction = {
      reserveTokens = 32768;
      keepRecentTokens = 32768;
    };
    packages = [ ]; # the key has to stay: it overwrites what settings.json already declares
    retry = {
      maxRetries = 5;
      baseDelayMs = 10000;
      provider.maxRetryDelayMs = 160000;
    };
    terminal = {
      showTerminalProgress = true;
      trueColor = true;
    };
  };

  settingsFile = pkgs.writeText "pi-settings.json" (builtins.toJSON piSettings);

  # settings.json is merged: pi writes its own keys into it; models.json is read-only to pi.
  mergeSettings = pkgs.writeShellApplication {
    name = "pi-settings-merge";
    runtimeInputs = [ pkgs.jq ];
    text = # bash
      ''
        dir="$HOME/${agentDir}"
        mkdir -p "$dir"

        settings="$dir/settings.json"
        tmp="$(mktemp "$dir/settings.json.XXXXXX")"
        if [ -f "$settings" ]; then
          jq -s '.[0] * .[1]' "$settings" ${settingsFile} > "$tmp"
        else
          printf '%s\n' '{}' | jq -s '.[0] * .[1]' - ${settingsFile} > "$tmp"
        fi
        chmod 0600 "$tmp"
        if [ ! -f "$settings" ] || ! cmp -s "$tmp" "$settings"; then
          mv "$tmp" "$settings"
        else
          rm "$tmp"
        fi
      '';
  };
in
{
  home.packages = [
    pkgs.agent-browser
    piPkg
  ];

  home.sessionVariables = {
    PI_WEBFETCH_BIN = "${pkgs.agent-browser}/bin/agent-browser";
    # SearXNG runs on the framework box, not here.
    SEARXNG_URL = "http://${settings.searchDomain}:${toString settings.searxngPort}";
  };

  # No themes: Noctalia's `pi-agent` template writes ~/.pi/agent/themes/noctalia.json.
  home.file = {
    # The router answers 401 without a key; `apiKey` reads the untracked secrets/ file at request
    # time, so no secret is in git.
    "${agentDir}/models.json".source = ./models.json;
    "${agentDir}/APPEND_SYSTEM.md".source = ./APPEND_SYSTEM.md;
    # Compaction delegated to the summarizer subagent, whose window clips the conversation.
    "${agentDir}/extensions/compact-delegate".source = ./extensions/compact-delegate;
    "${agentDir}/extensions/llama-compat".source = ./extensions/llama-compat;
    # Prefill/decode progress, KV reuse and speculative-decode acceptance under the input box.
    "${agentDir}/extensions/llama-dx".source = ./extensions/llama-dx;
    # web_search against the SearXNG on the framework box, reached through SEARXNG_URL.
    "${agentDir}/extensions/searxng".source = ./extensions/searxng;
    "${agentDir}/extensions/subagents".source = ./extensions/subagents;
    # web_fetch and web_interact, driven through agent-browser (see PI_WEBFETCH_BIN above).
    "${agentDir}/extensions/webfetch".source = ./extensions/webfetch;
    # One model at a time: the router keeps a single preset resident.
    "${agentDir}/subagents.json".source = ./subagents.json;
    # Linked one by one: `${agentDir}/subagents` already exists and holds the concurrency store's state.
    "${agentDir}/subagents/assistant.md".source = ./subagents/assistant.md;
    "${agentDir}/subagents/coder.md".source = ./subagents/coder.md;
    "${agentDir}/subagents/researcher.md".source = ./subagents/researcher.md;
    "${agentDir}/subagents/reviewer.md".source = ./subagents/reviewer.md;
    "${agentDir}/subagents/summarizer.md".source = ./subagents/summarizer.md;
    "${agentDir}/subagents/worker.md".source = ./subagents/worker.md;
    "${agentDir}/prompts" = {
      source = ./prompts;
      recursive = true;
    };
  };

  home.activation.piSettingsMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] (lib.getExe mergeSettings);
}
