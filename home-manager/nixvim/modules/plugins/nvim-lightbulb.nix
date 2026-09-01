{ ... }:
{
  plugins.nvim-lightbulb = {
    enable = true;

    settings = {
      # Upstream ships `autocmd.enabled = false`, i.e. no CursorHold autocmd is
      # created and the bulb never shows unless this is flipped.
      autocmd.enabled = true;

      # Nerd Font glyph instead of the 2-column 💡 emoji (BerkeleyMono Nerd Font).
      sign.text = "󰌶";
    };
  };
}
