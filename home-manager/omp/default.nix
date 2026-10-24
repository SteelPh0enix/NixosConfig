# oh-my-pi (`omp`), a pi fork, installed beside pi rather than instead of it: it reads and writes
# only ~/.omp, so nothing here touches the ~/.pi/agent files home-manager/pi owns. Its own flake
# ships a home-manager module, so unlike pi this is mostly upstream options. No extensions are
# installed - pi's are written against pi's API, and omp's own tool set covers most of them.
{ omp, pkgs, ... }:
let
  agentDir = ".omp/agent";
  ompBin = "${omp.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/omp";
in
{
  imports = [ omp.homeManagerModules.default ];

  programs.omp = {
    enable = true;

    # omp writes config.yml itself (/settings, /model, onboarding) and this activation replaces the
    # file outright, so the whole tuned surface is declared here: a value changed in /settings
    # reverts to one of these on the next switch unless it is re-declared below. Only runtime
    # state (sessions/, last-changelog-version, the *.db files) is left for omp to own.
    # The values below are the ones the live instance runs with, so a switch reproduces that
    # configuration instead of omp's own defaults.
    settings = {
      # The presets that take no xhigh clamp down to their top rung (see models.yml).
      defaultThinkingLevel = "xhigh";
      # Same default as pi: the framework box's router. Quote a selector holding spaces.
      modelRoles.default = "framework/qwen-next";
      # Session titles, the tool-issue judge and speculative compaction ride the smol/tiny
      # roles; unset, they would resolve through the built-in cloud chains (pinned off at the
      # bottom of this file), so they point at cyber-tiel-coder instead: this router's fast
      # coder, abliterated, and on the pc rather than the framework box, so the side
      # requests those features make never contend with the primary. Its two slots run on one
      # unified KV pool: one holds the quick smol/tiny requests, one the single subagent that
      # `task.maxConcurrency` allows.
      modelRoles.smol = "llama-pc/cyber-tiel-coder";
      modelRoles.tiny = "llama-pc/cyber-tiel-coder";
      # The generic task/sonic/scout agents share that free cyber-tiel slot. `agents/` pins its
      # own two agents explicitly - coder and reviewer both on cyber-tiel - so they hold their
      # slot whichever model the session happens to be on. `slow` stays unset, so anything asking
      # for it gets the configured default, which is the slot the main session holds.
      modelRoles.task = "llama-pc/cyber-tiel-coder";
      # No advisor: it keeps a model resident to re-read every turn, which on a two-slot unified
      # pool is a whole slot spent on a passive second opinion. Reviewing happens on purpose
      # instead, as a `reviewer` spawn that reads the tree itself. `omp --advisor` or `/advisor on`
      # turns the subsystem on for one session.
      advisor.enabled = false;
      # Search goes to the SearXNG on the framework box rather than through the default chain, which
      # would reach Parallel's keyless MCP and Exa first. Same instance and local name as pi's
      # searxng extension uses via SEARXNG_URL (home-manager/pi/default.nix): the hosts entry in
      # nixos/services.nix answers search.framework, and plain HTTP skips the TLS hop.
      modelRoles.web = "web/searxng";
      searxng.endpoint = "http://search.framework:7777";
      # No Exa key on this box, so the other half of that default chain stays off.
      exa.enabled = false;
      # Nothing leaves the box unless a selector says so explicitly. Every role resolves
      # through its fallback chain, and OpenRouter - the only cloud provider with a key here -
      # sits in the built-in chain of all of them: the unassigned vision role sent an image
      # question out that way. Pinning each chain that can fire passively to [] stops
      # resolution on this box: roles with a local primary fail visibly when their router
      # fails instead of retrying on the cloud, roles without one resolve to nothing and their
      # callers use the session model. Reaching an external model stays possible explicitly,
      # through modelRoles or by editing a chain. web is included so a keyless cloud search
      # cannot take over when the local SearXNG is down; advisor, image, speech and dictation
      # stay unpinned - their subsystems are off, so enabling one is the opt-in.
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
      # Attached-image descriptions ride the vision role; off rather than failing on every
      # attach.
      images.describeForTextModels = false;

      # Local GPUs do the work, so token counts are the only way to notice a compaction storm or a
      # runaway subagent; there is no bill to read instead.
      display.showTokenUsage = true;
      display.shimmer = "kitt";
      # The fleet is one slot wide, so a collapsed list hides which agent is busy: list them all.
      display.pinnedAgents = "full";
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

      # The band composer: the status band sits above the prompt instead of a bottom bar.
      composer.shape = "band";
      composer.tokenRate = true;

      # The full preset: model, path, git, the token counters, cost and the clock.
      statusLine.preset = "full";
      statusLine.separator = "powerline";
      statusLine.contextLine = "annotated";
      statusLine.sessionAccent = true;
      # The terminal's own background instead of the theme's, so the line paints no bar of its own.
      statusLine.transparent = true;
      statusLine.compactThinkingLevel = false;
      statusLine.showHookStatus = true;

      # The retro theme pair, and nerd glyphs for the icons that have them.
      theme.dark = "dark-retro";
      theme.light = "light-retro";
      symbolPreset = "nerd";

      tui.resizeScrollback = "append";
      tui.titleSpinner = "braille";
      tui.tight = false;
      tui.vimMode = true;
      tui.vimModeDisplay = "text";
      # Clicks focus the agent rows, and paths and URLs become clickable links.
      tui.mouse = true;
      tui.hyperlinks = "always";
      # Rows pushed off by the HUD go to the scrollback instead of being dropped.
      tui.completeScrollback = true;

      terminal.showProgress = true;
      readLineNumbers = true;
      personality = "pragmatic";
      treeFilterMode = "default";
      todo.eager = "always";

      task.showResolvedModelBadge = true;
      # One task at a time: every subagent runs on cyber-tiel-coder, whose two-slot unified
      # pool leaves exactly one slot free of the smol/tiny traffic, and the pc router keeps a
      # single preset resident, so a second parallel task costs a model swap before a token.
      task.maxConcurrency = 1;
      # Always delegate: the fleet is one slot wide, so the main session is the one that talks to
      # the user.
      task.eager = "preferred";
      # Subagent results come back validated against the caller's schema instead of as prose.
      task.structured = true;
      # Subagents pick their own reasoning effort, and may use the lsp tool as well.
      task.enableEffort = true;
      task.enableLsp = true;
      # A subagent that asks for isolation gets a worktree of its own, so it never writes into
      # the checkout the main session works in.
      task.isolation.enabled = true;

      contextPromotion.enabled = false;
      compaction.methodOrder = [
        "remote"
        "shake"
        "soft"
        "handoff"
      ];
      compaction.idleEnabled = false;
      # 75% of the model's window instead of the reserve-based default (85%). omp-vcc owns the
      # compaction itself, so this is the point at which its summary replaces the history.
      compaction.thresholdPercent = 75;
      # Only bites on models that also declare maxContextWindow (models.yml); a plain contextWindow
      # stays fixed in both modes.
      extendedContext = true;

      edit.mode = "hashline";
      read.renderMarkdown = true;
      lsp.formatOnWrite = true;
      lsp.diagnosticsOnEdit = true;
      astGrep.enabled = true;
      checkpoint.enabled = true;
      # Every session opens in plan mode, so nothing is written before the plan is approved.
      plan.defaultOnStartup = true;
      # The approved plan stays in the session rather than becoming a file in the tree.
      plan.autosave = false;

      memory.backend = "off";

      # The interceptor blocks shell calls that a dedicated tool covers, and names the tool.
      bashInterceptor.enabled = true;
      # The github tool reads issues, PRs and Actions.
      github.enabled = true;
      # A failed turn notifies, like a finished one does.
      error.notify = "on";

      # Nothing goes to omp's cloud: /collab, /share and /stream stay on this box.
      collab.relayUrl = "none";
      share.serverUrl = "none";
      stream.serverUrl = "none";

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
  # Task agents discovered from the agent dir (`omp://task-agent-discovery.md`), so the fleet is
  # these files plus the bundled ones. Read at spawn, so an edit needs no rebuild once deployed -
  # but deployment is a switch. Read-only, so the store symlink is fine here too.
  home.file."${agentDir}/agents".source = ./agents;
  # omp-vcc's own config, the source of truth for how it compacts: with
  # overrideDefaultCompaction set, VCC replaces the host's LLM summary on threshold and
  # overflow instead of falling back to it. The plugin writes this file itself when it is
  # missing, so it is declared here to keep the copy in the repo authoritative; the keys it
  # leaves out come from the plugin's own defaults.
  home.file.".omp/omp-vcc/config.json".source = ./omp-vcc-config.json;

  # omp-vcc is the omp-native port of sting8k/pi-vcc: compaction becomes a deterministic
  # extraction instead of an LLM summary, and the history it drops stays searchable through
  # vcc_recall. The upstream module has no plugin option and ~/.omp/plugins is runtime state it
  # never touches, so the install is declared here. The check keeps the activation offline once
  # the plugin is in place.
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
