{ ... }:
{
  # Upstream defaults are all we want: rendering is on for `markdown` buffers (insert mode
  # shows the raw source), headings/code blocks add gutter signs - harmless with
  # `signcolumn = "yes"`, set `settings.sign.enabled = false` if it gets busy.
  # Toggle at runtime with `:RenderMarkdown toggle|buf_toggle|preview`.
  plugins.render-markdown.enable = true;
}
