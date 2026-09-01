{ ... }:
{
  # ---- Extra packages (LSPs, tools, runtime deps) ----
  extraLuaPackages = _p: [ ];
  extraPython3Packages = _p: [ ];

  viAlias = true;
  vimAlias = true;
  withNodeJs = true;

  # ---- Leader key ----
  # NOTE: this must be a literal " ". `vim.g.mapleader = '<Space>'` does NOT expand
  # keycodes in Lua - it silently kept the default `\` leader.
  # `globals` is emitted in `extraConfigLuaPre` (before keymaps & plugin setup),
  # which is why it replaces the old `extraConfigLua` hack.
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  # ---- Colourscheme ----
  colorschemes.cyberdream = {
    enable = true;
    settings = {
      transparent = false;
      terminal_colors = true;
    };
  };

  # ---- Diagnostics ----
  diagnostic.settings = {
    severity_sort = true;
    update_in_insert = false;
    float = {
      border = "rounded";
      source = true;
    };
  };

  # ---- Global keymaps ----
  # LSP buffer mappings live in `plugins.lsp.keymaps` below (attached per-buffer).
  keymaps = [
    # --- Save / Close ---
    {
      # `<Cmd>` (capital C) writes without leaving insert mode
      mode = [
        "n"
        "i"
      ];
      key = "<C-s>";
      action = "<Cmd>w<CR>";
      options.desc = "Save file";
    }
    {
      key = "<leader>q";
      action = "<Cmd>q<CR>";
      options.desc = "Close buffer";
    }

    # --- File tree ---
    {
      key = "<leader>fs";
      action = "<Cmd>NvimTreeToggle<CR>";
      options.desc = "Toggle file tree";
    }

    # --- Diagnostics ---
    # `vim.diagnostic.goto_next/prev` are deprecated in Nvim 0.12; `jump` is the replacement.
    {
      key = "]d";
      action.__raw = "function() vim.diagnostic.jump({ count = 1, float = true }) end";
      options.desc = "Next diagnostic";
    }
    {
      key = "[d";
      action.__raw = "function() vim.diagnostic.jump({ count = -1, float = true }) end";
      options.desc = "Previous diagnostic";
    }
    {
      key = "<leader>d";
      action.__raw = "function() vim.diagnostic.open_float() end";
      options.desc = "Line diagnostics";
    }

    # --- Quickfix navigation ---
    {
      key = "]l";
      action = "<Cmd>cnext<CR>";
      options.desc = "Next quickfix item";
    }
    {
      key = "[l";
      action = "<Cmd>cprev<CR>";
      options.desc = "Previous quickfix item";
    }

    # --- Clear search highlight ---
    {
      key = "<Esc>";
      action = "<Cmd>nohlsearch<CR>";
      # nowait: don't make Esc wait for `timeoutlen` before firing
      options = {
        desc = "Clear search highlight";
        nowait = true;
        silent = true;
      };
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

  # ---- Plugins ----
  plugins = {
    cmp.enable = true;
    fzf-lua.enable = true;
    gitsigns.enable = true;
    lualine.enable = true;
    nvim-autopairs.enable = true;
    nvim-lightbulb.enable = true;
    nvim-tree.enable = true;
    render-markdown.enable = true;
    rustaceanvim.enable = true;
    treesitter.enable = true;
    web-devicons.enable = true;
  };

  # ---- Completion (nvim-cmp) ----
  plugins.cmp = {
    autoEnableSources = true;

    settings = {
      completion = {
        keyword_length = 2;
        completeopt = "menu,menuone,noinsert,noselect";
      };

      formatting.fields = [
        "kind"
        "abbr"
      ];

      window = {
        completion.border = "rounded";
        documentation.border = "rounded";
      };

      mapping = {
        "<C-Space>" = "cmp.mapping.complete()";
        "<C-d>" = "cmp.mapping.scroll_docs(-4)";
        "<C-f>" = "cmp.mapping.scroll_docs(4)";
        "<C-e>" = "cmp.mapping.close()";
        "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), { 'i', 's' })";
        "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), { 'i', 's' })";
        "<C-j>" = "cmp.mapping.select_next_item()";
        "<C-k>" = "cmp.mapping.select_prev_item()";
        "<CR>" = "cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Insert, select = false })";
        "<C-CR>" = "cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Insert, select = true })";
      };

      sources = [
        {
          name = "nvim_lsp";
          group_index = 1;
        }
        {
          name = "path";
          group_index = 1;
        }
        {
          name = "buffer";
          group_index = 2;
        }
      ];
    };

    # Command-line completion
    cmdline = {
      ":" = {
        completion.completeopt = "menu,menuone,noinsert";
        sources = [ { name = "cmdline"; } ];
      };
    };
  };

  # ---- Tree-sitter ----
  # NOTE: enabling `nvim-treesitter` alone does nothing on the `main` branch: Nvim does not
  # start parsers by itself, the features have to be turned on explicitly.
  plugins.treesitter = {
    highlight.enable = true;
    indent.enable = true;
    folding = {
      enable = true;
    };
  };

  # ---- fzf-lua ----
  plugins.fzf-lua = {
    profile = "default";

    settings = {
      winopts = {
        height = 0.5;
        width = 0.9;
      };
    };

    keymaps = {
      # Files / grep
      "<leader>ff" = "files";
      "<leader>fg" = "live_grep";
      "<leader>fr" = "oldfiles";
      "<leader>fb" = "buffers";

      # LSP
      "<leader>sl" = "lsp_document_symbols";
      "<leader>sw" = "lsp_live_workspace_symbols";
      "<leader>sd" = "diagnostics";

      # Misc
      "<leader>sh" = "help_tags";
      "<leader>sk" = "keymaps";

      # Git
      "<leader>gc" = "git_commits";
      "<leader>gb" = "git_branches";
      "<leader>gt" = "git_status";
    };
  };

  # ---- LSP ----
  plugins.lsp = {
    enable = true;

    servers.clangd.enable = true;

    # Buffer-local keymaps, registered on `LspAttach` (replaces the old global
    # `<cmd>lua vim.lsp.buf.*<CR>` mappings).
    keymaps = {
      # `vim.lsp.buf.<action>`
      lspBuf = {
        "gd" = "definition";
        "gD" = "declaration";
        "gr" = "references";
        "gi" = "implementation";
        "go" = "type_definition";
        "K" = "hover";
        "<leader>ca" = "code_action";
        "<leader>rn" = "rename";
        "<leader>cf" = "format";
      };

      # Anything that is not a plain `vim.lsp.buf` call
      extra = [
        {
          key = "<leader>ls";
          action = "<Cmd>LspStart<CR>";
          options.desc = "Start LSP";
        }
        {
          key = "<leader>lx";
          action = "<Cmd>LspStop<CR>";
          options.desc = "Stop LSP";
        }
        {
          key = "<leader>lR";
          action = "<Cmd>LspRestart<CR>";
          options.desc = "Restart LSP";
        }
      ];
    };
  };

  # ---- Nvim-tree configuration ----
  plugins.nvim-tree.openOnSetup = false;

}
