# oh-my-pi (`omp`), a pi fork, installed beside pi rather than instead of it: it reads and writes
# only ~/.omp, so nothing here touches the ~/.pi/agent files home-manager/pi owns. Its own flake
# ships a home-manager module, so unlike pi this is mostly upstream options. No extensions are
# installed - pi's are written against pi's API, and omp's own tool set covers most of them.
{ omp, ... }:
let
  agentDir = ".omp/agent";
in
{
  imports = [ omp.homeManagerModules.default ];

  programs.omp = {
    enable = true;

    # omp writes config.yml itself (/settings, /model, onboarding) and this activation replaces the
    # file outright, so the whole tuned surface is declared here: a value changed in /settings
    # reverts to one of these on the next switch unless it is re-declared below. Only runtime
    # state (sessions/, last-changelog-version, the *.db files) is left for omp to own.
    settings = {
      # The presets that take no xhigh clamp down to their top rung (see models.yml).
      defaultThinkingLevel = "xhigh";
      # Same default as pi: the framework box's router. Quote a selector holding spaces.
      modelRoles.default = "llama-main/Qwen 3.8 Flash Next";
      # The built-in smol/tiny chains are cloud models, and this box has no cloud credential for
      # any of them: unset, they resolve to nothing, so session titles, the tool-issue judge and
      # speculative compaction all fall back to the session model. minicpm is this router's 3-slot
      # preset - a 35B-A3B MoE, so roomy enough for the parallel side requests those features make
      # (and for `judge`, which resolves through @tiny then @smol). Its slots run on one unified
      # KV pool: the advisor and the quick requests take a slot or two, one task takes one, and
      # the rest stays free for the pi fleet on the same router.
      modelRoles.smol = "llama-pc/minicpm";
      modelRoles.tiny = "llama-pc/minicpm";
      # Subagents follow the same shift: the bundled task/sonic/scout agents (@task, @smol) run
      # on minicpm; the reviewer agents take @slow, which falls back to the configured
      # default - qwen-next has two slots on its router, so one can hold a subagent while the
      # session keeps working. No explicit `slow` needed.
      modelRoles.task = "llama-pc/minicpm";
      # A second pair of eyes: minicpm passively reviews each turn from its own context with
      # read/grep/glob, steering on concerns and blockers. No effort suffix, so it reviews at
      # medium - quick reviews, no xhigh sprawl.
      modelRoles.advisor = "llama-pc/minicpm";
      advisor.enabled = true;
      # Search goes to the SearXNG on the framework box rather than through the default chain, which
      # would reach Parallel's keyless MCP and Exa first. Same instance and local name as pi's
      # searxng extension uses via SEARXNG_URL (home-manager/pi/default.nix): the hosts entry in
      # nixos/services.nix answers search.framework, and plain HTTP skips the TLS hop.
      modelRoles.web = "web/searxng";
      searxng.endpoint = "http://search.framework:7777";
      # No Exa key on this box, so the other half of that default chain stays off.
      exa.enabled = false;

      # Local GPUs do the work, so token counts are the only way to notice a compaction storm or a
      # runaway subagent; there is no bill to read instead.
      display.showTokenUsage = true;
      display.shimmer = "kitt";
      display.pinnedAgents = "collapsed";
      display.subagentLivePreview = true;
      display.showTurnTime = true;
      display.cacheMissMarker = true;

      # The wizard gate: omp records finished onboarding as setupVersion in config.yml, and the
      # activation above wipes that key on every switch, so the next launch sees version 0 and
      # replays the wizard. Nothing it offers (sign-in, theme, model pick) is undeclared here, so
      # keep it off rather than re-declaring a version number that has to be bumped per release.
      startup.setupWizard = false;
      # The flake pins the revision; nix decides when omp updates, not the TUI.
      startup.checkUpdate = false;

      composer.shape = "box";
      composer.tokenRate = true;

      statusLine.preset = "nerd";
      statusLine.separator = "powerline";
      statusLine.contextLine = "annotated";
      statusLine.sessionAccent = true;
      statusLine.transparent = false;
      statusLine.compactThinkingLevel = false;
      statusLine.showHookStatus = true;

      tui.resizeScrollback = "rebuild";
      tui.titleSpinner = "braille";
      tui.tight = false;
      tui.vimMode = true;
      tui.vimModeDisplay = "text";

      terminal.showProgress = true;
      readLineNumbers = true;
      personality = "pragmatic";
      treeFilterMode = "default";

      task.showResolvedModelBadge = true;
      # One task at a time: minicpm's 3-slot pool covers the advisor, the quick smol/tiny
      # requests and one task without contention, and its unified pool only shrinks per request
      # the more slots run - a second concurrent task halves what the first can hold for no
      # throughput the reviewer and titles don't need anyway.
      task.maxConcurrency = 1;

      contextPromotion.enabled = false;
      compaction.methodOrder = [
        "remote"
        "shake"
        "soft"
        "handoff"
      ];
      compaction.idleEnabled = false;

      edit.mode = "hashline";
      read.renderMarkdown = true;
      lsp.formatOnWrite = true;
      lsp.diagnosticsOnEdit = true;
      astGrep.enabled = true;
      checkpoint.enabled = true;
      plan.autosave = false;

      memory.backend = "off";

      providers.tinyModelDevice = "default";
    };
  };

  # The house rules carried over from pi's APPEND_SYSTEM.md, ported rather than copied: pi's
  # ripgrep/fd and codemode lines are about tools omp replaces with its own (grep/glob, eval).
  # omp reads the file from the agent dir at every start, so a symlink like models.yml's works.
  home.file."${agentDir}/APPEND_SYSTEM.md".source = ./APPEND_SYSTEM.md;
  # Providers and models, ported from home-manager/pi/models.json. omp only reads this one (it
  # writes a models.yml solely to migrate an old models.json, which we do not ship), so unlike
  # config.yml a store symlink is fine.
  home.file."${agentDir}/models.yml".source = ./models.yml;
}
