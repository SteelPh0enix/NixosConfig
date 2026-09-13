{ ... }:
{
  # CLI formatters with LSP fallback (`lsp_format = "fallback"`), which is what makes
  # `<leader>cf` work in filetypes no formatting client covers (fish, JSON, ...).
  # `autoInstall` resolves every name in `formatters_by_ft` to a nix package on the wrapper
  # PATH, so none of these need an entry in nixos/packages/dev.nix.
  plugins.conform-nvim = {
    enable = true;
    autoInstall.enable = true;

    settings = {
      notify_no_formatters = false;
      notify_on_error = true;

      # Defaults for every conform.format() call, so the keymap and format-on-save cannot
      # drift apart. `timeout_ms` must live *here*: setup() ignores a top-level one and you
      # fall back to 1000ms, which rustfmt/clang-format can exceed on a cold cache.
      default_format_opts = {
        lsp_format = "fallback";
        timeout_ms = 5000;
      };

      # Repeated from default_format_opts on purpose: NixVim's `toLuaObject` drops an empty
      # `format_on_save = { }`, and conform only checks truthiness, so the table itself is
      # what enables the BufWritePre autocmd. Delete this key for manual-only formatting.
      format_on_save = {
        lsp_format = "fallback";
        timeout_ms = 5000;
      };

      formatters_by_ft = {
        c = [ "clang-format" ];
        cpp = [ "clang-format" ];
        rust = [ "rustfmt" ];
        # ruff formats too, but only one of the two runs (lsp_format = "fallback") and the
        # CLI keeps working in buffers with no client attached.
        python = [ "ruff_format" ];
        sh = [ "shfmt" ];
        bash = [ "shfmt" ];
        fish = [ "fish_indent" ];
        # Same binary nixd uses (settings.formatting.command); listed so formatting also
        # works in a .nix buffer with no client attached.
        nix = [ "nixfmt" ];
        lua = [ "stylua" ];
        json = [ "jq" ];
        toml = [ "taplo" ];
      };
    };
  };

  # Top-level keymaps, NOT plugins.lsp.keymaps: those are emitted on LspAttach (buffer-local,
  # only once a client is attached) - the opposite of what conform needs.
  # Note conform provides no `:Format` command, only `:ConformInfo`.
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
