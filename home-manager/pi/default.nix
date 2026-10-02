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
    # SearXNG is served by fwpc, so the extension's 127.0.0.1:7777 default never connects from other hosts.
    environment.SEARXNG_URL.value = "http://steelph0enix.framework:7777";
    # llama-compat auto-detects llama-named providers; these routers are qwen-named, so they are listed.
    environment.LLAMA_COMPAT_URLS.value = "http://steelph0enix.framework:33333,http://steelph0enix.pc:51536";

    # Handed to pi as CLI flags on every run instead of being placed in the agent dir.
    rules = ./APPEND_SYSTEM.md;
    extensions = [
      ./extensions/searxng.ts
      ./extensions/webfetch.ts
      ./extensions/llama-compat/index.ts
    ];
    # No theme here: Noctalia's community `pi-agent` template (hyprland/noctalia.nix) writes
    # ~/.pi/agent/themes/noctalia.json from the live palette. Passing a copy via `themes` would
    # only collide on the name `noctalia`.
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
      # +name keeps read, bash, edit, write and adds codemode
      defaultTools = [ "+codemode" ];
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
