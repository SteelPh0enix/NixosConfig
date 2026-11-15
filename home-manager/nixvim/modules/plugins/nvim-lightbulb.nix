_: {
  # Code actions use Neovim's defaults; signature help lives in lsp.nix.
  plugins.nvim-lightbulb = {
    enable = true;

    settings = {
      # Upstream default is off: no CursorHold autocmd, no bulb.
      autocmd.enabled = true;

      # setup() pushes updatetime 200 after NixVim's block; negative leaves it alone.
      autocmd.updatetime = -1;

      # Nerd Font glyph instead of the 2-column lightbulb emoji.
      sign.text = "󰌶";
    };
  };
}
