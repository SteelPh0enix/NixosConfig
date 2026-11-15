# The pi coding agent and its resources. Anything not listed here stays pi-owned: auth.json,
# sessions/, trust.json, and the settings.json keys pi writes itself.
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
    # xhigh where the preset has a rung for it; a model whose `thinkingLevelMap` maps xhigh to
    # null gets no effort sent.
    defaultThinkingLevel = "xhigh";
    theme = "noctalia";
    transport = "auto";
    treeFilterMode = "default";
    enableSkillCommands = true;
    enableInstallTelemetry = false;
    # +codemode keeps the built-in tools and adds codemode.
    defaultTools = [ "+codemode" ];
    # reserveTokens also caps the summary; keepRecentTokens survives unsummarized.
    compaction = {
      reserveTokens = 32768;
      keepRecentTokens = 32768;
    };
    packages = [ ]; # keep the key: it overwrites whatever settings.json already declares
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

  # settings.json is merged, not replaced: pi writes its own keys into it. models.json is
  # read-only to pi.
  mergeSettings = pkgs.writeShellApplication {
    name = "pi-settings-merge";
    runtimeInputs = [ pkgs.jq ];
    text = # bash
      ''
        dir="$HOME/${agentDir}"
        mkdir -p "$dir"

        # Managed keys win, keys pi wrote itself survive.
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
    # The webfetch extension drives agent-browser (its own lookup paths are npm-based).
    pkgs.agent-browser
    piPkg
  ];

  # LLAMA_COMPAT_DEBUG=1 shows what llama-compat changed in the catalog.
  home.sessionVariables = {
    PI_WEBFETCH_BIN = "${pkgs.agent-browser}/bin/agent-browser";
    SEARXNG_URL = "http://${settings.searchDomain}:${toString settings.searxngPort}";
    # LLAMA_COMPAT_DEBUG = "1";
  };

  home.file = {
    # `apiKey` holds a `!command` that reads the key at request time, so the secret stays out of
    # the store.
    "${agentDir}/models.json".source = ./models.json;
    "${agentDir}/APPEND_SYSTEM.md".source = ./APPEND_SYSTEM.md;
    # Compaction handled by the summarizer subagent, clipped by its own window.
    "${agentDir}/extensions/compact-delegate".source = ./extensions/compact-delegate;
    "${agentDir}/extensions/llama-compat".source = ./extensions/llama-compat;
    # Needs --slots on each instance; LLAMA_DX_DEBUG=1 logs polls.
    "${agentDir}/extensions/llama-dx".source = ./extensions/llama-dx;
    "${agentDir}/extensions/searxng".source = ./extensions/searxng;
    "${agentDir}/extensions/subagents".source = ./extensions/subagents;
    "${agentDir}/extensions/webfetch".source = ./extensions/webfetch;
    # One model at a time: the router keeps a single preset resident.
    "${agentDir}/subagents.json".source = ./subagents.json;
    # Read at startup, so an edit needs a pi restart. Linked one by one: the directory already
    # holds the lease database.
    "${agentDir}/subagents/assistant.md".source = ./subagents/assistant.md;
    "${agentDir}/subagents/coder.md".source = ./subagents/coder.md;
    "${agentDir}/subagents/researcher.md".source = ./subagents/researcher.md;
    "${agentDir}/subagents/reviewer.md".source = ./subagents/reviewer.md;
    "${agentDir}/subagents/summarizer.md".source = ./subagents/summarizer.md;
    "${agentDir}/subagents/worker.md".source = ./subagents/worker.md;
    # Noctalia palette. This copy is the source on this host, so edit it here and re-activate.
    "${agentDir}/themes/noctalia.json".source = ./themes/noctalia.json;
    "${agentDir}/prompts" = {
      source = ./prompts;
      recursive = true;
    };
  };

  home.activation.piSettingsMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] (lib.getExe mergeSettings);
}
