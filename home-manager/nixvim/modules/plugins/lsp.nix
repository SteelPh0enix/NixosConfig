{ ... }:
{
  # ---- LSP ----
  plugins.lsp = {
    enable = true;

    servers.clangd.enable = true;

    # Buffer-local keymaps, registered on `LspAttach` (replaces the old global
    # `<cmd>lua vim.lsp.buf.*<CR>` mappings).
    keymaps = {
      # `vim.lsp.buf.<action>`
      lspBuf = {
        "gd" = "definition";
        "gD" = "declaration";
        "gr" = "references";
        "gi" = "implementation";
        "go" = "type_definition";
        "K" = "hover";
        "<leader>ca" = "code_action";
        "<leader>rn" = "rename";
        "<leader>cf" = "format";
      };

      # Anything that is not a plain `vim.lsp.buf` call
      extra = [
        {
          key = "<leader>ls";
          action = "<Cmd>LspStart<CR>";
          options.desc = "Start LSP";
        }
        {
          key = "<leader>lx";
          action = "<Cmd>LspStop<CR>";
          options.desc = "Stop LSP";
        }
        {
          key = "<leader>lR";
          action = "<Cmd>LspRestart<CR>";
          options.desc = "Restart LSP";
        }
      ];
    };
  };
}
