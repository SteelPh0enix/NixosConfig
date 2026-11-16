_: {
  # Indicator only: code actions run through Neovim's own `gra`/`grn` defaults.
  plugins.nvim-lightbulb = {
    enable = true;

    settings = {
      # Upstream default is `autocmd.enabled = false`: no CursorHold autocmd, no bulb.
      autocmd.enabled = true;

      # setup() pushes its own `updatetime` after nixvim's block; negative = leave it alone.
      autocmd.updatetime = -1;

      # Nerd Font glyph instead of the 2-column lightbulb emoji.
      sign.text = "󰌶";
    };
  };
}
