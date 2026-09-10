{ ... }:
{
  # Indicator only - code actions run through Neovim's own `gra`/`grn`/`grr`/... defaults
  # (:help lsp-defaults). `<C-S>` signature help is shadowed by the `<C-s>` save mapping,
  # which is why plugins.lsp-signature is enabled in lsp.nix instead.
  plugins.nvim-lightbulb = {
    enable = true;

    settings = {
      # Upstream default is `autocmd.enabled = false`: no CursorHold autocmd, no bulb.
      autocmd.enabled = true;

      # setup() pushes its own `updatetime` (200) into `vim.opt` *after* NixVim's block,
      # clobbering options.nix. Negative = leave it alone.
      autocmd.updatetime = -1;

      # Nerd Font glyph instead of the 2-column lightbulb emoji.
      sign.text = "󰌶";
    };
  };
}
