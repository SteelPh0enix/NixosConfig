{ ... }:
{
  # ---- Tree-sitter ----
  # NOTE: enabling `nvim-treesitter` alone does nothing on the `main` branch: Nvim does not
  # start parsers by itself, the features have to be turned on explicitly.
  plugins.treesitter = {
    enable = true;

    highlight.enable = true;
    indent.enable = true;
    folding = {
      enable = true;
    };
  };
}
