_: {
  # Must be a literal " ": Lua does not expand keycodes in `vim.g.mapleader`. `globals` is emitted
  # in extraConfigLuaPre, before keymaps and plugin setup.
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  keymaps = [
    {
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

    # Global on purpose: the `<leader>l{s,x,R}` controls in lsp.nix exist only once a client
    # attached, which is exactly when this is needed.
    {
      key = "<leader>li";
      action = "<Cmd>checkhealth vim.lsp<CR>";
      options.desc = "LSP health";
    }

    # Not <leader>d: that prefix belongs to nvim-dap, and mapping both it and <leader>dX would
    # make the bare press wait out `timeoutlen`.
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
      # nowait, or Esc waits for `timeoutlen` before firing.
      options = {
        desc = "Clear search highlight";
        nowait = true;
        silent = true;
      };
    }
  ];
}
