_: {
  # CLI formatters with LSP fallback; `autoInstall` puts every name in `formatters_by_ft` on the
  # wrapper PATH, so none need an entry in nixos/packages/dev.nix.
  plugins.conform-nvim = {
    enable = true;
    autoInstall.enable = true;

    settings = {
      notify_no_formatters = false;
      notify_on_error = true;

      # `timeout_ms` must live here: setup() ignores a top-level one, and rustfmt can exceed the
      # 1000ms fallback on a cold cache.
      default_format_opts = {
        lsp_format = "fallback";
        timeout_ms = 5000;
      };

      # Repeated from default_format_opts on purpose: `toLuaObject` drops an empty
      # `format_on_save = { }`, and conform only checks truthiness.
      format_on_save = {
        lsp_format = "fallback";
        timeout_ms = 5000;
      };

      formatters_by_ft = {
        c = [ "clang-format" ];
        cpp = [ "clang-format" ];
        rust = [ "rustfmt" ];
        # ruff formats too, but only one of the two runs (lsp_format = "fallback").
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
