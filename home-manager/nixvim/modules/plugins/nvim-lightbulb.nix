{ ... }:
{
  plugins.nvim-lightbulb = {
    enable = true;

    # The bulb is only an indicator ("code actions exist here"), it has no mappings of
    # its own. Actions run through Neovim's own defaults (:help lsp-defaults), which are
    # registered unconditionally in $VIMRUNTIME/lua/vim/_core/defaults.lua:
    #
    #   gra   code action (normal + visual)   grx  run code lens     gO   document symbols
    #   grn   rename                          grr  references        gri  implementation
    #   grt   type definition                 K    hover (set per-buffer on LspAttach)
    #   <C-S> signature help (insert) - shadowed here by the <C-s> save mapping, which is
    #         why plugins.lsp-signature is enabled instead.
    #
    # Also built-in, handy next to the above:  ]d / [d  diagnostics,
    #   ]q / [q / ]Q / [Q  quickfix,  ]l / [l / ]L / [L  location list.
    #
    # In the `gra` picker: type to filter, <C-j>/<C-k> to move, <CR> to apply, <Esc> to
    # cancel. Entries are suffixed with `[client]` when several servers reply.
    #
    # The bulb itself appears on CursorHold, i.e. after `updatetime`; note that this
    # plugin sets `updatetime` to its own `autocmd.updatetime` (200) unless that is
    # negative.
    settings = {
      # Upstream ships `autocmd.enabled = false`, i.e. no CursorHold autocmd is
      # created and the bulb never shows unless this is flipped.
      autocmd.enabled = true;

      # Upstream default is 200 and `setup()` does `if autocmd.updatetime > 0 then
      # vim.opt.updatetime = it end` - which runs *after* NixVim's `vim.opt` block and
      # silently clobbers the global `updatetime = 300` from options.nix.
      # Negative = leave `updatetime` alone.
      autocmd.updatetime = -1;

      # Nerd Font glyph instead of the 2-column 💡 emoji (BerkeleyMono Nerd Font).
      sign.text = "󰌶";
    };
  };
}
