_: {
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

    # Same engine and .gitignore handling as fzf-lua's live_grep, so both agree on hits.
    grepprg = "rg --vimgrep --smart-case";
    grepformat = "%f:%l:%c:%m,%f:%l:%m";

    termguicolors = true;
    number = true;
    relativenumber = true;
    cursorline = true;
    # No global `colorcolumn`: the per-filetype guides in `autocmds.nix` mirror the formatter
    # configs (rustfmt 100, ruff 88, clang-format 80/120, nixfmt 100).

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

    undofile = true;
    swapfile = false;
    confirm = true;

    # Reload buffers changed on disk; the FileChangedShellPost autocmd announces it.
    autoread = true;

    # histogram handles moved blocks better, vertical avoids `nvim -d`, internal skips the binary.
    diffopt = [
      "internal"
      "algorithm:histogram"
      "indent-heuristic"
      "vertical"
    ];

    scrolloff = 8;
    sidescrolloff = 4;
    sidescroll = 1;

    # "auto" would shift the text as soon as gitsigns/the lightbulb add their first sign.
    signcolumn = "yes";

    laststatus = 3;

    list = true;
    listchars = "tab:>-,trail:·,extends:»,precedes:«,eol:¬";
    breakindent = true;

    # Build artefacts and VCS internals: out of `:find`, `:browse` and tab-completion.
    wildignore =
      "node_modules/**,.git/**,result/**,target/**,build/**,_build/**,.venv/**,__pycache__/**"
      + ",*.o,*.obj,*.so,*.rlib";
    wildignorecase = true;
    # nvim-cmp sets its own for insert mode; this drops Nvim's `popup`, which overlaps cmp's
    # documentation window.
    completeopt = [
      "menu"
      "menuone"
      "noinsert"
      "noselect"
    ];

    # `foldclose`, not Vim-only `foldclosed` (that E474s the whole setting).
    fillchars = "fold:─,foldopen:┄,foldclose:┈,foldsep:│";

    # treesitter folding sets foldmethod=expr but foldlevel defaults to 0, which opens every
    # file fully folded. 99 = start unfolded; zM/zR/zc/za still work.
    foldlevel = 99;
    foldlevelstart = 99;
    foldcolumn = "auto:2";
    foldnestmax = 4;
  };
}
