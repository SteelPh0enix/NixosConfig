{ ... }:
{
  # ---- Extra packages (LSPs, tools, runtime deps) ----
  extraLuaPackages = _p: [ ];
  extraPython3Packages = _p: [ ];

  viAlias = true;
  vimAlias = true;
  withNodeJs = true;

  # ---- Keymaps ----
  keymaps = [
    {
      key = "<leader>ev";
      action = ":e $MYVIMRC<CR>";
      options.desc = "Edit Nixvim config";
    }
    {
      key = "<leader>w";
      action = "<cmd>w<CR>";
      options.desc = "Save file";
    }
    {
      key = "<leader>q";
      action = "<cmd>q<CR>";
      options.desc = "Close buffer";
    }
    {
      key = "]l";
      action = "<cmd>cnext<CR>";
      options.desc = "Next quickfix item";
    }
    {
      key = "[l";
      action = "<cmd>cprev<CR>";
      options.desc = "Previous quickfix item";
    }
  ];

  # ---- Neovim options ----
  opts = {
    encoding = "utf-8";
    langmenu = "en_US";

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
    cursorcolumn = false;
    colorcolumn = "80";

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
  };

  globals.loaded_ruby_provider = 0;
  globals.loaded_perl_provider = 0;
  globals.loaded_python_provider = 0;

  # ---- Plugins ----
  plugins = {
    cmp.enable = true;
    diffview.enable = true;
    gitsigns.enable = true;
    lualine.enable = true;
    markdown-preview.enable = true;
    neoconf.enable = true;
    nvim-autopairs.enable = true;
    nvim-lightbulb.enable = true;
    treesitter.enable = true;
    obsidian.enable = false;
    render-markdown.enable = true;
    rustaceanvim.enable = true;
    tmux-navigator.enable = true;
    web-devicons.enable = true;
  };

}
