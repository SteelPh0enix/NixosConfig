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
    # --- Save / Close ---
    {
      key = "<C-s>";
      action = "<cmd>w<CR>";
      options.desc = "Save file";
    }
    {
      key = "<leader>q";
      action = "<cmd>q<CR>";
      options.desc = "Close buffer";
    }

    # --- File tree ---
    {
      key = "<leader>fs";
      action = "<cmd>NvimTreeToggle<CR>";
      options.desc = "Toggle file tree";
    }

    # --- LSP navigation ---
    {
      key = "gd";
      action = "<cmd>lua vim.lsp.buf.definition()<CR>";
      options.desc = "Go to definition";
    }
    {
      key = "gD";
      action = "<cmd>lua vim.lsp.buf.declaration()<CR>";
      options.desc = "Go to declaration";
    }
    {
      key = "gr";
      action = "<cmd>lua vim.lsp.buf.references()<CR>";
      options.desc = "Find references";
    }
    {
      key = "gi";
      action = "<cmd>lua vim.lsp.buf.implementation()<CR>";
      options.desc = "Go to implementation";
    }
    {
      key = "go";
      action = "<cmd>lua vim.lsp.buf.type_definition()<CR>";
      options.desc = "Go to type definition";
    }

    # --- Hover / Diagnostics ---
    {
      key = "K";
      action = "<cmd>lua vim.lsp.buf.hover()<CR>";
      options.desc = "Hover details";
    }
    {
      key = "]d";
      action = "<cmd>lua vim.diagnostic.goto_next()<CR>";
      options.desc = "Next diagnostic";
    }
    {
      key = "[d";
      action = "<cmd>lua vim.diagnostic.goto_prev()<CR>";
      options.desc = "Previous diagnostic";
    }

    # --- Quickfix navigation ---
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
  extraConfigLua = ''
    vim.g.mapleader = ' '
  '';

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
  };

  # ---- Plugins ----
  plugins = {
    cmp.enable = true;

    gitsigns.enable = true;
    lualine.enable = true;
    nvim-autopairs.enable = true;
    nvim-lightbulb.enable = true;
    cmp-nvim-lsp.enable = true;
    cmp-path.enable = true;
    nvim-tree.enable = true;
    treesitter.enable = true;
    obsidian.enable = false;
    render-markdown.enable = true;
    rustaceanvim.enable = true;
    web-devicons.enable = true;
  };

  # ---- LSP Server Configuration ----
  plugins.lsp = {
    enable = true;
    servers.clangd.enable = true;
  };

  # ---- Nvim-tree configuration ----
  plugins.nvim-tree.openOnSetup = false;

}
