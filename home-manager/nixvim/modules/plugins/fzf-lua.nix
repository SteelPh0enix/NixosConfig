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

      # Man pages: the doc lookup for C/C++/POSIX symbols (`printf`, `pthread_create`,
      # `gitattributes`) that LSP hover cannot give - clangd only knows what is in the
      # compilation database, and `K` is already hover. Needs `man` on PATH (system default).
      "<leader>sm" = "man_pages";

      # Git
      "<leader>gc" = "git_commits";
      "<leader>gb" = "git_branches";
      "<leader>gt" = "git_status";
    };
  };
}
