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
  #
  # Neovim already provides, unconditionally: `]d`/`[d` (diagnostics), `]q`/`[q`
  # (quickfix), `]l`/`[l` + `]L`/`[L` (location list), `gra`/`grn`/`grr`/`gri`/`grt`/
  # `grx`/`gO` (LSP), `gc` (comment). `K` (hover) is set per-buffer on LspAttach.
  # Only map what is actually missing from that list.
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
    # Not <S-H>/<S-L>: Neovim cannot tell `h` from `<S-h>`, so those would clobber
    # the native H/L (jump to first/last line of the window).
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

    # --- Diagnostics ---
    {
      key = "<leader>d";
      action.__raw = "function() vim.diagnostic.open_float() end";
      options.desc = "Line diagnostics";
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
