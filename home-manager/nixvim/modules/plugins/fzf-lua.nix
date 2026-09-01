{ ... }:
{
  # ---- fzf-lua ----
  plugins.fzf-lua = {
    enable = true;
    profile = "default";

    settings = {
      winopts = {
        height = 0.5;
        width = 0.9;
      };
    };

    keymaps = {
      # Files / grep
      "<leader>ff" = "files";
      "<leader>fg" = "live_grep";
      "<leader>fr" = "oldfiles";
      "<leader>fb" = "buffers";

      # LSP
      "<leader>sl" = "lsp_document_symbols";
      "<leader>sw" = "lsp_live_workspace_symbols";
      "<leader>sd" = "diagnostics";

      # Misc
      "<leader>sh" = "help_tags";
      "<leader>sk" = "keymaps";

      # Git
      "<leader>gc" = "git_commits";
      "<leader>gb" = "git_branches";
      "<leader>gt" = "git_status";
    };
  };
}
