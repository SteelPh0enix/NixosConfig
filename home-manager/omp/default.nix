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
    # file outright, so a change made in the TUI returns to these values on the next switch. Keep it
    # to what must hold, and leave the rest for omp to own.
    settings = {
      # The presets that take no xhigh clamp down to their top rung (see models.yml).
      defaultThinkingLevel = "xhigh";
      # Same default as pi: the framework box's router. Quote a selector holding spaces.
      modelRoles.default = "llama-main/Qwen 3.8 Flash Next";
      # The built-in smol/tiny chains are cloud models, and this box has no cloud credential for
      # any of them: unset, they resolve to nothing, so session titles, the tool-issue judge and
      # speculative compaction all fall back to the session model. sharp-spark is this box's own
      # router's 4-slot preset - fast, and roomy enough for the parallel side requests those
      # features make (and for `judge`, which resolves through @tiny then @smol).
      modelRoles.smol = "llama-pc/sharp-spark";
      modelRoles.tiny = "llama-pc/sharp-spark";
      # Local GPUs do the work, so token counts are the only way to notice a compaction storm or a
      # runaway subagent; there is no bill to read instead.
      display.showTokenUsage = true;
      # The wizard gate: omp records finished onboarding as setupVersion in config.yml, and the
      # activation above wipes that key on every switch, so the next launch sees version 0 and
      # replays the wizard. Nothing it offers (sign-in, theme, model pick) is undeclared here, so
      # keep it off rather than re-declaring a version number that has to be bumped per release.
      startup.setupWizard = false;
      # Search goes to the SearXNG on the framework box rather than through the default chain, which
      # would reach Parallel's keyless MCP and Exa first. Same instance and local name as pi's
      # searxng extension uses via SEARXNG_URL (home-manager/pi/default.nix): the hosts entry in
      # nixos/services.nix answers search.framework, and plain HTTP skips the TLS hop.
      modelRoles.web = "web/searxng";
      searxng.endpoint = "http://search.framework:7777";
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
