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

    # `:grep`/`:lg` through ripgrep: same engine and .gitignore handling as fzf-lua's
    # live_grep and todo-comments' search, so all three agree on hits.
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
    # undodir already defaults to $XDG_STATE_HOME/nvim/undo, so undofile is all it takes.
    undofile = true;
    swapfile = false; # undo files cover crash recovery, .swp is just noise
    confirm = true; # prompt instead of dropping an unsaved buffer on :q/:bnext conflicts

    # ---- Files / external tools ----
    # Reload buffers changed on disk (nixfmt elsewhere, git checkout, codegen); the
    # FileChangedShellPost autocmd announces it.
    autoread = true;

    # histogram handles moved blocks better, vertical avoids `nvim -d`, internal keeps the
    # external `diff` binary out of the wrapper.
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

    # "auto" would shift the text as soon as gitsigns/the lightbulb add their first sign.
    signcolumn = "yes";

    # One global statusline (lualine); also what makes the fillchars separators apply.
    laststatus = 3;

    # ---- Whitespace ----
    list = true;
    listchars = "tab:>-,trail:·,extends:»,precedes:«,eol:¬";
    # `linebreak` is already on -> align wrapped lines with the original indent
    breakindent = true;

    # ---- Wildmenu / completion ----
    # Build artefacts and VCS internals polluting `:find`, `:browse` and tab-completion.
    wildignore =
      "node_modules/**,.git/**,result/**,target/**,build/**,_build/**,.venv/**,__pycache__/**"
      + ",*.o,*.obj,*.so,*.rlib";
    wildignorecase = true;
    # Native completion; nvim-cmp sets its own for insert mode. Drops Nvim's `popup`, which
    # overlaps cmp's documentation window.
    completeopt = [
      "menu"
      "menuone"
      "noinsert"
      "noselect"
    ];

    # Note: `foldclose`, not Vim-only `foldclosed` (that E474s the whole setting).
    fillchars = "fold:─,foldopen:┄,foldclose:┈,foldsep:│";

    # ---- Folding ----
    # treesitter folding sets foldmethod=expr but foldlevel defaults to 0, which opens every
    # file fully folded (very visible on nix). 99 = start unfolded, zM/zR/zc/za still work.
    foldlevel = 99;
    foldlevelstart = 99;
    foldcolumn = "auto:2"; # markers only where there actually are folds
    foldnestmax = 4;
  };
}
