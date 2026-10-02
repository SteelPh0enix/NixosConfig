# The pi coding agent and its resources. Everything else in ~/.pi/agent stays pi-owned:
# auth.json, sessions/, trust.json, and settings.json keys pi writes itself.
{ pkgs, pi, ... }:
{
  imports = [ pi.homeModules.default ];

  # The webfetch extension drives agent-browser (its own lookup paths are npm-based).
  home.packages = [ pkgs.agent-browser ];

  programs.pi.coding-agent = {
    enable = true;

    environment.PI_WEBFETCH_BIN.value = "${pkgs.agent-browser}/bin/agent-browser";

    # Handed to pi as CLI flags on every run instead of being placed in the agent dir.
    rules = ./APPEND_SYSTEM.md;
    extensions = [
      ./extensions/searxng.ts
      ./extensions/webfetch.ts
    ];
    themes = [ ./themes/noctalia.json ];
    promptTemplates = [ ./prompts ];

    # Installed into ~/.pi/agent/models.json only when that file is missing; rm it to re-seed.
    models = ./models.json;

    # jq-merged into ~/.pi/agent/settings.json at every start, so unlisted keys survive.
    settings = {
      defaultProvider = "qwen-next";
      defaultModel = "Qwen 3.8 Flash Next";
      defaultThinkingLevel = "high";
      theme = "noctalia";
      transport = "auto";
      treeFilterMode = "default";
      enableSkillCommands = true;
      enableInstallTelemetry = false;
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
  };
}
