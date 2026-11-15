_: {
  # Must be a literal " ": `mapleader` does not expand keycodes in Lua.
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  # Neovim already provides `]d`/`[d`, `]q`/`[q`, `]l`/`[l`, `gr*`, `gO` and `gc`; only the
  # gaps are mapped here. Plugin mappings live next to their plugin.
  keymaps = [
    {
      # `<Cmd>` writes without leaving insert mode.
      mode = [
        "n"
        "i"
      ];
      key = "<C-s>";
      action = "<Cmd>w<CR>";
      options.desc = "Save file";
    }
    {
      key = "<leader>w";
      action = "<Cmd>w<CR>";
      options.desc = "Save file";
    }
    {
      key = "<leader>q";
      action = "<Cmd>confirm bdelete<CR>";
      options.desc = "Close buffer";
    }

    # Not <S-H>/<S-L>: Neovim cannot tell `h` from `<S-h>`, so those clobber the native H/L.
    {
      key = "<leader>bn";
      action = "<Cmd>bnext<CR>";
      options.desc = "Next buffer";
    }
    {
      key = "<leader>bp";
      action = "<Cmd>bprevious<CR>";
      options.desc = "Previous buffer";
    }

    # Global: the `<leader>l` controls in lsp.nix only exist once a client attached.
    {
      key = "<leader>li";
      action = "<Cmd>checkhealth vim.lsp<CR>";
      options.desc = "LSP health";
    }

    # Not <leader>d: that prefix belongs to nvim-dap.
    {
      key = "<leader>dd";
      action.__raw = "function() vim.diagnostic.open_float() end";
      options.desc = "Line diagnostics";
    }

    {
      mode = "t";
      key = "<Esc>";
      action = "<C-\\><C-n>";
      options.desc = "Exit terminal input mode";
    }

    {
      key = "<Esc>";
      action = "<Cmd>nohlsearch<CR>";
      options = {
        desc = "Clear search highlight";
        nowait = true;
        silent = true;
      };
    }
  ];
}
