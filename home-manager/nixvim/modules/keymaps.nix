{ ... }:
{
  # ---- Leader key ----
  # NOTE: this must be a literal " ". `vim.g.mapleader = '<Space>'` does NOT expand
  # keycodes in Lua - it silently kept the default `\` leader.
  # `globals` is emitted in `extraConfigLuaPre` (before keymaps & plugin setup),
  # which is why it replaces the old `extraConfigLua` hack.
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  # ---- Global keymaps ----
  # Plugin-specific mappings live next to their plugin:
  #   - LSP buffer mappings:   plugins/lsp.nix        (attached per-buffer)
  #   - fzf-lua pickers:       plugins/fzf-lua.nix
  #   - file tree toggle:      plugins/nvim-tree.nix
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
}
