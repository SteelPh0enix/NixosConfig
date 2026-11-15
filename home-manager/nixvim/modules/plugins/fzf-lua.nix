_: {
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
      "<leader>ff" = "files";
      "<leader>fg" = "live_grep";
      "<leader>fr" = "oldfiles";
      "<leader>fb" = "buffers";

      "<leader>sl" = "lsp_document_symbols";
      "<leader>sw" = "lsp_live_workspace_symbols";
      "<leader>sd" = "diagnostics";

      "<leader>sh" = "help_tags";
      "<leader>sk" = "keymaps";

      # Doc lookup for C/C++/POSIX symbols, which LSP hover cannot give.
      "<leader>sm" = "man_pages";

      "<leader>gc" = "git_commits";
      "<leader>gb" = "git_branches";
      "<leader>gt" = "git_status";
    };
  };
}
