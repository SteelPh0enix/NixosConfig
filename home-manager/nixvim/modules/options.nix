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

    termguicolors = true;
    number = true;
    relativenumber = true;
    cursorline = true;
    colorcolumn = "80,100,120";

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
    wildignore = "node_modules/**,.git/**,*.o,*.obj,result";
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
