_: {
  # CLI formatters with LSP fallback, so `<leader>cf` works where no client formats.
  # `autoInstall` resolves each name to a nix package on the wrapper PATH.
  plugins.conform-nvim = {
    enable = true;
    autoInstall.enable = true;

    settings = {
      notify_no_formatters = false;
      notify_on_error = true;

      # Defaults for every format call; `timeout_ms` must live here, a top-level one is ignored.
      default_format_opts = {
        lsp_format = "fallback";
        timeout_ms = 5000;
      };

      # Repeated on purpose: NixVim drops an empty `format_on_save = { }`, and conform needs
      # the table itself to enable the BufWritePre autocmd.
      format_on_save = {
        lsp_format = "fallback";
        timeout_ms = 5000;
      };

      formatters_by_ft = {
        c = [ "clang-format" ];
        cpp = [ "clang-format" ];
        rust = [ "rustfmt" ];
        python = [ "ruff_format" ];
        sh = [ "shfmt" ];
        bash = [ "shfmt" ];
        fish = [ "fish_indent" ];
        nix = [ "nixfmt" ];
        lua = [ "stylua" ];
        json = [ "jq" ];
        toml = [ "taplo" ];
      };
    };
  };

  # Top-level keymaps: plugins.lsp.keymaps are only emitted on LspAttach. conform has no
  # `:Format` command.
  keymaps = [
    {
      key = "<leader>cf";
      action.__raw = "function() require('conform').format() end";
      options.desc = "Format (conform, LSP fallback)";
    }
    {
      key = "<leader>cF";
      action.__raw = "function() vim.lsp.buf.format() end";
      options.desc = "Format (LSP clients only)";
    }
  ];
}
