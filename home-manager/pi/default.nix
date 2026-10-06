# The pi coding agent and its resources: the package comes from pi's own flake, everything else is
# plain home-manager. Anything not listed here stays pi-owned: auth.json, sessions/, trust.json, and
# the settings.json keys pi writes itself.
{
  lib,
  pkgs,
  pi,
  ...
}:
let
  piPkg = pi.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  agentDir = ".pi/agent";

  settings = {
    defaultProvider = "llama-main";
    defaultModel = "Qwen 3.8 Flash Next";
    defaultThinkingLevel = "high";
    theme = "noctalia";
    transport = "auto";
    treeFilterMode = "default";
    enableSkillCommands = true;
    enableInstallTelemetry = false;
    # +name keeps read, bash, edit, write and adds codemode
    defaultTools = [ "+codemode" ];
    # Compaction triggers at contextWindow - reserveTokens, the summary's own output is capped at
    # 0.8 * reserveTokens, and keepRecentTokens is what survives a compaction unsummarized. At the
    # 16384 default a 262k-context model kept truncating the summaries it needed to stay under.
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

  settingsFile = pkgs.writeText "pi-settings.json" (builtins.toJSON settings);

  # Both files stay real files pi can rewrite; rm models.json to re-seed it from the repo.
  seedAgentDir = pkgs.writeShellApplication {
    name = "pi-agent-seed";
    runtimeInputs = [ pkgs.jq ];
    text = # bash
      ''
        dir="$HOME/${agentDir}"
        mkdir -p "$dir"

        if [ ! -e "$dir/models.json" ]; then
          install -m 0600 ${./models.json} "$dir/models.json"
        fi

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

  # Read by the extensions at runtime; LLAMA_COMPAT_DEBUG=1 shows what llama-compat changed in the catalog.
  home.sessionVariables = {
    PI_WEBFETCH_BIN = "${pkgs.agent-browser}/bin/agent-browser";
    # SearXNG runs on fwpc, so the extension's 127.0.0.1:7777 default never connects from here.
    SEARXNG_URL = "http://search.framework:7777";
    # LLAMA_COMPAT_DEBUG = "1";
  };

  # pi's conventional agent-dir locations: APPEND_SYSTEM.md extends the system prompt, extensions/
  # loads .ts files and directories with an index.ts, prompts/ becomes slash commands.
  # No themes: Noctalia's community `pi-agent` template (hyprland/noctalia.nix) writes
  # ~/.pi/agent/themes/noctalia.json from the live palette, and a copy here would only collide on
  # the name `noctalia`.
  home.file = {
    "${agentDir}/APPEND_SYSTEM.md".source = ./APPEND_SYSTEM.md;
    "${agentDir}/extensions/searxng.ts".source = ./extensions/searxng.ts;
    "${agentDir}/extensions/webfetch.ts".source = ./extensions/webfetch.ts;
    "${agentDir}/extensions/llama-compat".source = ./extensions/llama-compat;
    # llama-dx shows what the server is doing with the current request: prefill progress and speed,
    # tokens left to process, decode speed, KV reuse and speculative-decode acceptance, in a bar under
    # the input box. Needs --slots on each instance (a llama.cpp default). LLAMA_DX_DEBUG=1 logs polls.
    # The whole directory, since it is several .ts files importing each other. test-utils/ holds the
    # dev-only scripts: preview, harness against a real instance, check against a fake one.
    "${agentDir}/extensions/llama-dx".source = ./extensions/llama-dx;
    # Link every template by name instead of replacing the whole directory.
    "${agentDir}/prompts" = {
      source = ./prompts;
      recursive = true;
    };
  };

  home.activation.piAgentSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] (lib.getExe seedAgentDir);
}
