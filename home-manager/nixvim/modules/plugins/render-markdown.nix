{ ... }:
{
  # ---- render-markdown.nvim (Markdown rendering) ----
  # ON BY DEFAULT - nothing to "trigger". nixvim only emits `require("render-markdown").setup({})`
  # (checked in the built init.lua), so all upstream defaults apply, `enabled = true` included:
  # every `markdown` buffer is rendered as soon as it is displayed, and edits keep it in sync
  # via a `debounce = 100` ms re-parse of the *viewport* only (not the whole file).
  # Verified against the built nvim:
  #   :lua print(require('render-markdown').get())  ->  true
  #   :echo exists(':RenderMarkdown')               ->  2
  #
  # What the upstream defaults actually scope:
  #   file_types   = { "markdown" }              - only markdown buffers
  #   injections   = { gitcommit.enabled = true } - commit messages get rendered too
  #   render_modes = { "n", "c", "t" }           - insert mode always shows the raw source,
  #                                                which is why marks "disappear" while typing
  #   max_file_size = 10 (MB)                    - bigger files are skipped entirely
  #   win_options  = conceallevel 3 while rendered, the window's own value when not
  #
  # Runtime toggling - the nixvim module has NO `toggle` config key (its settingsOptions are
  # only preset / enabled / injections / max_file_size / debounce / win_options / overrides),
  # so it has to go through the plugin's own command or API:
  #   :RenderMarkdown              enable (the bare command means "enable"!)
  #   :RenderMarkdown disable      off everywhere
  #   :RenderMarkdown toggle       global toggle      = require('render-markdown').toggle()
  #   :RenderMarkdown buf_toggle   current buffer only = require('render-markdown').buf_toggle()
  #   :RenderMarkdown preview      rendered read-only copy in a right split, source stays raw
  #   :RenderMarkdown debug        overlay of every mark the plugin placed
  #
  # Keymap deliberately left off (rendering is on, so a bind would only be an off-switch).
  # If wanted, buffer-local is the nicer variant - `<leader>md` for the current file only:
  #   keymaps = [ {
  #     key = "<leader>md";
  #     action.__raw = "function() require('render-markdown').buf_toggle() end";
  #     options.desc = "Toggle markdown rendering (buffer)";
  #   } ];
  #
  # NOTE: `sign.enabled` is true upstream, so headings/code blocks place signs in the gutter.
  # Harmless since Tier B pinned `signcolumn = "yes"` (no more text shifting), but if the
  # markdown gutter gets busy: `settings.sign.enabled = false;`.
  plugins.render-markdown.enable = true;
}
