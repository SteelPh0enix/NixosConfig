{ ... }:
{
  # ---- Neovim options ----
  opts = {
    tabstop = 2;
    shiftwidth = 2;
    softtabstop = 0;
    expandtab = true;
    smartindent = true;
    autoindent = true;
    linebreak = true;
    showbreak = "↪ ";

    hlsearch = true;
    incsearch = true;
    ignorecase = true;
    smartcase = true;
    wildmode = "list:longest,list:full";

    # `:grep` / `:lg` go through ripgrep: same engine (and same .gitignore handling) as
    # fzf-lua's live_grep and todo-comments' search.command, so the three agree on hits.
    # `--smart-case` pairs with `ignorecase`/`smartcase` above; `%f:%l:%c:%m` matches
    # rg's `file:line:col:message`, the second pattern covers rg lines without a column.
    grepprg = "rg --vimgrep --smart-case";
    grepformat = "%f:%l:%c:%m,%f:%l:%m";

    termguicolors = true;
    number = true;
    relativenumber = true;
    cursorline = true;
    # No global `colorcolumn`: the per-filetype guides in `autocmds.nix` mirror the actual
    # formatter configs (rustfmt 100, ruff 88, clang-format 80/120, nixfmt 100).

    # Touch/yank with the mouse without giving up the keyboard selections.
    # "a" = all modes (Nvim's own default is "nvi"), including the command-line window.
    mouse = "a";

    splitbelow = true;
    splitright = true;

    clipboard = "unnamedplus";

    backspace = [
      "eol"
      "start"
      "indent"
    ];

    timeoutlen = 500;
    updatetime = 300;

    # ---- Undo / recovery ----
    # `undodir` already defaults to `$XDG_STATE_HOME/nvim/undo` (Neovim creates it on demand),
    # so `undofile = true` is all that is needed for history to survive a quit.
    undofile = true;
    # Swap files only add `.swp` noise; undo files cover crash recovery (see `:help undo-file`).
    swapfile = false;
    # Prompt instead of silently dropping an unsaved buffer on `:q`/`:enew`/`:bnext` conflicts.
    confirm = true;

    # ---- Files / external tools ----
    # Reload a buffer that changed on disk (nixfmt in another shell, `git checkout`, codegen)
    # when it has no unsaved changes; the `FileChangedShellPost` autocmd in `autocmds.nix`
    # is what makes that reload visible instead of silent.
    autoread = true;

    # `:diffthis` / `nvim -d`: histogram is much better on moved code blocks, and
    # `vertical` puts the two windows side by side without needing `-d`.
    # `internal` uses Nvim's own diff engine (no external `diff` binary in the wrapper).
    diffopt = [
      "internal"
      "algorithm:histogram"
      "indent-heuristic"
      "vertical"
    ];

    # ---- Cursor / scrolling ----
    scrolloff = 8; # keep context above/below the cursor
    sidescrolloff = 4; # ... and horizontally (only visible with `nowrap`/long lines)
    sidescroll = 1; # smooth 1-column steps instead of a jump

    # Always reserve the sign column: with "auto" the text shifts as soon as
    # gitsigns/the lightbulb add their first sign.
    signcolumn = "yes";

    # One global statusline (lualine) instead of one per window.
    # Note: `fillchars` horiz/vert separators only take effect with laststatus = 3.
    laststatus = 3;

    # ---- Whitespace ----
    list = true;
    listchars = "tab:>-,trail:·,extends:»,precedes:«,eol:¬";
    # `linebreak` is already on -> align wrapped lines with the original indent
    breakindent = true;

    # ---- Wildmenu / completion ----
    # Build artefacts and VCS internals: these otherwise pollute `:find`, `:browse` and
    # tab-completion. (fzf-lua's `:Files` already honours .gitignore; this is the native side.)
    wildignore =
      "node_modules/**,.git/**,result/**,target/**,build/**,_build/**,.venv/**,__pycache__/**"
      + ",*.o,*.obj,*.so,*.rlib";
    wildignorecase = true;
    # nvim-cmp sets its own completeopt for insert mode; this covers native completion
    # (and drops Nvim's default `popup`, which overlaps cmp's own documentation window).
    completeopt = [
      "menu"
      "menuone"
      "noinsert"
      "noselect"
    ];

    # ---- Fill characters ----
    # Note: the item is `foldclose`, **not** `foldclosed` (`foldclosed` is Vim-only and
    # makes Neovim fail the whole setting with E474).
    fillchars = "fold:─,foldopen:┄,foldclose:┈,foldsep:│";

    # Folding
    # `plugins.treesitter.folding` sets `foldmethod=expr` per window, but `foldlevel`
    # defaults to 0 -> every fold opens closed (very obvious on nix files, where each
    # attrset/let/list is a fold). 99 = start fully unfolded; `zM`/`zR`/`zc`/`za` still work.
    foldlevel = 99;
    foldlevelstart = 99;
    foldcolumn = "auto:2"; # fold markers only when the window actually has folds
    # Cap the nesting depth so deeply nested attrsets don't turn into 6 columns of noise
    foldnestmax = 4;
  };
}
