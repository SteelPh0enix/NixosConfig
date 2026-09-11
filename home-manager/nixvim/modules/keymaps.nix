{ ... }:
{
  # Must be a literal " ": `vim.g.mapleader = '<Space>'` does not expand keycodes in Lua.
  # `globals` is emitted in extraConfigLuaPre, i.e. before keymaps and plugin setup.
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  # Plugin-specific mappings live next to their plugin (lsp.nix, fzf-lua.nix, nvim-tree.nix,
  # dap.nix). Neovim already provides `]d`/`[d`, `]q`/`[q`, `]l`/`[l`, the `gr*` LSP set, `gO`
  # and `gc` - only the gaps are mapped here.
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
      key = "<leader>w";
      action = "<Cmd>w<CR>";
      options.desc = "Save file";
    }
    {
      key = "<leader>q";
      action = "<Cmd>confirm bdelete<CR>";
      options.desc = "Close buffer";
    }

    # --- Buffer navigation ---
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

    # --- LSP status ---
    # Global on purpose: the `<leader>l{s,x,R}` controls in lsp.nix only exist once a client
    # attached, which is exactly when "why is nothing attached" is hardest to diagnose.
    {
      key = "<leader>li";
      action = "<Cmd>checkhealth vim.lsp<CR>";
      options.desc = "LSP health";
    }

    # --- Diagnostics ---
    # Not <leader>d: that prefix belongs to nvim-dap, and mapping the prefix *and* <leader>dX
    # makes the bare press wait out `timeoutlen`. `<C-W>d` is the native equivalent.
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
}
