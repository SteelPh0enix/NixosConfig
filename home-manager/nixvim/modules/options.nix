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

    # Same engine and .gitignore handling as fzf-lua and todo-comments.
    grepprg = "rg --vimgrep --smart-case";
    grepformat = "%f:%l:%c:%m,%f:%l:%m";

    termguicolors = true;
    number = true;
    relativenumber = true;
    cursorline = true;
    # No global `colorcolumn`: the per-filetype guides in autocmds.nix mirror the formatters.
    # Mouse works in all modes, including the command-line window.
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

    # undodir defaults to $XDG_STATE_HOME/nvim/undo; .swp is noise next to undo files.
    undofile = true;
    swapfile = false;
    confirm = true;

    # Reload buffers changed on disk; autocmds.nix announces it.
    autoread = true;

    # internal keeps the external diff binary out; histogram handles moved blocks.
    diffopt = [
      "internal"
      "algorithm:histogram"
      "indent-heuristic"
      "vertical"
    ];

    scrolloff = 8;
    sidescrolloff = 4;
    sidescroll = 1;

    # "auto" would shift the text once gitsigns adds its first sign.
    signcolumn = "yes";

    # One global statusline (lualine).
    laststatus = 3;

    list = true;
    listchars = "tab:>-,trail:·,extends:»,precedes:«,eol:¬";
    breakindent = true;

    # Build artefacts and VCS internals polluting `:find` and tab-completion.
    wildignore =
      "node_modules/**,.git/**,result/**,target/**,build/**,_build/**,.venv/**,__pycache__/**"
      + ",*.o,*.obj,*.so,*.rlib";
    wildignorecase = true;
    # Native completion; nvim-cmp sets its own for insert mode.
    completeopt = [
      "menu"
      "menuone"
      "noinsert"
      "noselect"
    ];

    # `foldclose`, not Vim-only `foldclosed` (that E474s the whole setting).
    fillchars = "fold:─,foldopen:┄,foldclose:┈,foldsep:│";

    # treesitter folding leaves foldlevel=0, so every file would start folded.
    foldlevel = 99;
    foldlevelstart = 99;
    foldcolumn = "auto:2";
    foldnestmax = 4;
  };
}
