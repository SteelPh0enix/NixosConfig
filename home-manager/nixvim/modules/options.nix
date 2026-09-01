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
