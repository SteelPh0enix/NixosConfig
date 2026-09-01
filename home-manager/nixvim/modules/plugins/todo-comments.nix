{ ... }:
{
  # ---- todo-comments (todo-comment highlighting + picker) ----
  # Defaults kept on purpose (todo-comments.nvim 1.5.0 = what nixpkgs pins; nixvim's declared
  # defaults match it 1:1):
  #   keywords           FIX (+FIXME,BUG,FIXIT,ISSUE), TODO, HACK, WARN (+WARNING,XXX),
  #                      PERF (+OPTIM,PERFORMANCE,OPTIMIZE), NOTE (+INFO), TEST (+TESTING,...)
  #   highlight.pattern   .*<(KEYWORDS)\s*:  -> a colon after the keyword is required
  #   search.pattern      \b(KEYWORDS):      (ripgrep regex; colon required as well)
  # Keeping both colons is deliberate: the comments in this repo use the colon form
  # consistently (measured: 6 hits, 0 bare keywords), and the plugin's own colon-less variant
  # is documented as "you'll likely get false positives".
  #
  # `highlight.comments_only = true` (default) restricts *highlighting* to actual comments
  # (treesitter `@comment` capture, with a `synstack` fallback when no parser is active), but
  # the search behind the picker/quickfix is plain `rg` - so the colored warn echo at
  # scripts/cleanup-gitea-runners.sh:29 turns up in the list anyway. Not a misconfiguration;
  # filter in the picker if it bothers you.
  #
  # `signs = true` (default, priority 8) puts keyword icons in the sign column - no text
  # shifting since Tier B pinned `signcolumn = "yes"`. If the gutter gets crowded next to
  # gitsigns + nvim-lightbulb: `settings.signs = false;`, or per keyword via
  # `settings.keywords.PERF.signs = false;`.
  #
  # `search.command = "rg"` is satisfied by the nixvim module's `dependencies = [ "ripgrep" ]`
  # -> ripgrep 15.2.0 lands in the nvim wrapper's PATH (verified in the built wrapper), which
  # is also the binary fzf-lua's grep provider runs.
  plugins.todo-comments = {
    enable = true;

    # -> `<Cmd>TodoFzfLua<CR>`. The command is declared as
    #     command! -nargs=* TodoFzfLua lua require("todo-comments.fzf").todo() <args>
    # and `todo-comments.fzf` hands the generated ripgrep regex to fzf-lua's *grep* provider
    # (`fzf-lua.providers.grep`). fzf-lua's own todo picker is gone from the packaged build -
    # grepping its lua/ for "todo" returns nothing - so this plugin-side integration is the
    # only fzf route.
    #
    # Do NOT set `keymaps.todoFzfLua.keywords` / `.cwd` on this version: nixvim splices them
    # in *after* the call, and both variants were measured on the built nvim -
    #   keywords=TODO,FIX -> parses as a dead Lua assignment (statements need no separator),
    #                        so the filter is silently ignored
    #   cwd=/some/path    -> E5107: unexpected symbol near '/'
    keymaps.todoFzfLua.key = "<leader>st";
  };

  # ---- Jump between todos ----
  # NOT `]t`/`[t` (which the plugin's README suggests): Neovim 0.11+ ships those as
  # `:tnext`/`:tprevious` tag-stack motions (runtime/lua/vim/_core/defaults.lua), the same
  # trap as the `<S-H>`/`<S-L>` idea rejected in Tier A. Follows the `<leader>bn`/`<leader>bp`
  # precedent instead. Verified: `]t` still maps to the built-in, and `jump_next()` from line 1
  # of keymaps.nix lands on the note comment at 4:4.
  keymaps = [
    {
      key = "<leader>tn";
      action.__raw = "function() require('todo-comments').jump_next() end";
      options.desc = "Next todo comment";
    }
    {
      key = "<leader>tp";
      action.__raw = "function() require('todo-comments').jump_prev() end";
      options.desc = "Previous todo comment";
    }
  ];

  # ---- Other entry points, no keymap needed ----
  # 1.5.0 registers these in plugin/todo.vim. There is no plain `:TodoComments` any more
  # (`exists(':TodoComments') == 0` in the built nvim):
  #   :TodoQuickFix    -> quickfix list (`:copen`)
  #   :TodoLocList     -> location list (`:lopen`)
  #   :TodoTelescope   -> needs plugins.telescope (not enabled)
  #   :TodoTrouble     -> needs plugins.trouble   (not enabled)
  #   require('todo-comments').enable() / .disable()  -> start/stop highlighting
  # A snacks.nvim picker source is registered too, but only when snacks is present
  # (`if Snacks and pcall(require, "snacks.picker")`) - snacks is NOT required here.
}
