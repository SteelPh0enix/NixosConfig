# oh-my-pi (`omp`), a pi fork, installed beside pi. It reads and writes only ~/.omp, so nothing
# here touches the ~/.pi/agent files home-manager/pi owns. No extensions are installed.
{
  omp,
  pkgs,
  settings,
  ...
}:
let
  agentDir = ".omp/agent";
  ompBin = "${omp.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/omp";
in
{
  imports = [ omp.homeManagerModules.default ];

  programs.omp = {
    enable = true;

    # omp writes config.yml itself and this activation replaces it, so a value changed in
    # /settings reverts to one of these on the next switch.
    settings = {
      defaultThinkingLevel = "xhigh";
      modelRoles.default = "framework/Qwen 3.8 Flash Next";
      advisor.enabled = false;
      modelRoles.web = "web/searxng";
      searxng.endpoint = "http://${settings.searchDomain}:${toString settings.searxngPort}";
      exa.enabled = false;
      # Empty chains keep every role on this box; an explicitly named selector can still reach
      # a cloud model.
      retry.fallbackChains.default = [ ];
      retry.fallbackChains.smol = [ ];
      retry.fallbackChains.task = [ ];
      retry.fallbackChains.tiny = [ ];
      retry.fallbackChains.slow = [ ];
      retry.fallbackChains.plan = [ ];
      retry.fallbackChains.commit = [ ];
      retry.fallbackChains.memory = [ ];
      retry.fallbackChains.widget = [ ];
      retry.fallbackChains.vision = [ ];
      retry.fallbackChains.judge = [ ];
      retry.fallbackChains.web = [ ];
      images.describeForTextModels = false;

      display.showTokenUsage = true;
      display.shimmer = "kitt";
      display.pinnedAgents = "full";
      display.subagentLivePreview = true;
      display.showTurnTime = true;
      display.cacheMissMarker = true;

      # The activation replaces config.yml, so onboarding would replay on every switch.
      startup.setupWizard = false;
      # The flake pins the revision; nix decides when omp updates, not the TUI.
      startup.checkUpdate = false;

      composer.shape = "band";
      composer.tokenRate = true;

      statusLine.preset = "full";
      statusLine.separator = "powerline";
      statusLine.contextLine = "annotated";
      statusLine.sessionAccent = true;
      # The terminal's own background instead of the theme's.
      statusLine.transparent = true;
      statusLine.compactThinkingLevel = false;
      statusLine.showHookStatus = true;

      theme.dark = "dark-retro";
      theme.light = "light-retro";
      symbolPreset = "nerd";

      tui.resizeScrollback = "append";
      tui.titleSpinner = "braille";
      tui.tight = false;
      tui.vimMode = true;
      tui.vimModeDisplay = "text";
      # keeps the selection working, and scrolling without Shift
      tui.mouse = false;
      tui.hyperlinks = "always";
      tui.completeScrollback = true;

      terminal.showProgress = true;
      readLineNumbers = true;
      personality = "pragmatic";
      treeFilterMode = "default";
      todo.eager = "always";

      task.showResolvedModelBadge = true;
      # One task at a time: a second parallel task costs a model swap.
      task.maxConcurrency = 1;
      task.eager = "default";
      task.structured = true;
      task.enableEffort = true;
      task.enableLsp = true;
      # Isolated subagents get a worktree of their own.
      task.isolation.enabled = true;

      contextPromotion.enabled = false;
      compaction.methodOrder = [
        "remote"
        "shake"
        "soft"
        "handoff"
      ];
      compaction.idleEnabled = false;
      # omp-vcc replaces the history at 75% of the window.
      compaction.thresholdPercent = 75;
      extendedContext = true;

      edit.mode = "hashline";
      read.renderMarkdown = true;
      lsp.formatOnWrite = true;
      lsp.diagnosticsOnEdit = true;
      astGrep.enabled = true;
      checkpoint.enabled = true;
      plan.defaultOnStartup = false;
      plan.autosave = false;

      memory.backend = "off";

      # The interceptor blocks shell calls that a dedicated tool covers, and names the tool.
      bashInterceptor.enabled = true;
      github.enabled = true;
      error.notify = "on";
      # No idle recap: it asks gufo's only slot to restate the conversation.
      recap.enabled = false;

      # No telemetry or marketplace traffic leaves the box.
      telemetry.otlpExportEnabled = false;
      dev.autoqa = false;
      dev.autoqaConsent = "denied";
      dev.autoqaPush.endpoint = "";
      marketplace.autoUpdate = "off";

      # An empty share.serverUrl is not a disable - it falls back to my.omp.sh - hence "none".
      collab.relayUrl = "";
      collab.autoStart = "off";
      share.serverUrl = "none";
      stream.serverUrl = "none";
      images.urls.enabled = false;
    };
  };

  # House rules from pi's APPEND_SYSTEM.md, read from the agent dir at every start.
  home.file."${agentDir}/APPEND_SYSTEM.md".source = ./APPEND_SYSTEM.md;
  # Model catalog; omp only reads it, so a store symlink is fine.
  home.file."${agentDir}/models.yml".source = ./models.yml;
  # omp-vcc config. The plugin writes this file itself, so declaring it here keeps the repo copy
  # authoritative.
  home.file.".omp/omp-vcc/config.json".source = ./omp-vcc-config.json;

  # omp-vcc is the omp-native port of pi-vcc: deterministic compaction with searchable history.
  home.activation.ompVccPlugin = {
    before = [ ];
    after = [ "installPackages" ];
    data = ''
      if ! ${ompBin} plugin list --json 2>/dev/null | grep -q '"name": "omp-vcc"'; then
        ${ompBin} plugin install omp-vcc || echo "omp-vcc: install failed, run 'omp plugin install omp-vcc' by hand" >&2
      fi
    '';
  };
}
