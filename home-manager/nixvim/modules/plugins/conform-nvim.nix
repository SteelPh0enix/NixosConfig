{ ... }:
{
  # ---- conform-nvim (external formatters) ----
  # Before this, `<leader>cf` was `vim.lsp.buf.format`, which only does something where a
  # client implements `textDocument/formatting`: clangd (C/C++), nixd (Nix),
  # rust-analyzer (Rust) and lua_ls. basedpyright is a *type checker* - it never formats -
  # so Python/Bash/Fish/JSON/TOML had no formatter at all.
  #
  # `autoInstall` resolves each name in `formatters_by_ft` to a nix package
  # (conform-nvim/formatter-packages.nix, else `pkgs.<name>`) and adds it to the nvim
  # wrapper's PATH, so none of these need a matching entry in `nixos/packages/dev.nix`.
  # Verified in the built wrapper: shfmt, fish, jq, stylua, taplo, ruff, rustfmt,
  # nixfmt, clang-tools are all on its PATH. `:ConformInfo` shows what resolves per buffer.
  plugins.conform-nvim = {
    enable = true;
    autoInstall.enable = true;

    settings = {
      notify_no_formatters = false;
      notify_on_error = true;

      # Defaults for every `conform.format()` call - both `<leader>cf` and format-on-save
      # merge these, so the two paths cannot drift apart.
      #
      # NOTE: `timeout_ms` belongs *here*, not at the top level of `settings`.
      # `conform.setup()` reads exactly: formatters, formatters_by_ft, default_format_opts,
      # log_level, notify_on_error, notify_no_formatters, format_on_save, format_after_save
      # (`---@class (exact) conform.setupOpts`) - a top-level `timeout_ms` is silently
      # dropped and you fall back to the hardcoded 1000ms, which rustfmt/clang-format can
      # exceed on a cold cache.
      default_format_opts = {
        # "fallback" = run the CLI formatter, use the LSP only when there is none.
        # (`lsp_fallback = true` is the pre-9.0 spelling; nixpkgs pins conform 9.1.0, where
        # it survives only as a compat shim inside format(). `lsp_format` is also the key
        # nixvim's `default_format_opts` submodule actually declares.)
        lsp_format = "fallback";
        timeout_ms = 5000;
      };

      # Any table here enables the BufWritePre autocmd (conform only checks truthiness), so
      # the two keys below are *not* needed - they are repeated from default_format_opts on
      # purpose:
      # NixVim's `toLuaObject` runs with `removeEmptyAttrValues = true` (lib/to-lua.nix) and
      # silently drops a plain `format_on_save = { }` from the generated setup() call.
      # Measured: setup() came out with no `format_on_save` key and
      # `nvim_get_autocmds({ event = "BufWritePre", group = "Conform" })` was `{}` -
      # i.e. format-on-save looked configured but was not. Its documented escape hatch
      # `{ __empty = null; }` does not work on this option either: `rawLua.check` accepts
      # anything with an `__empty` key, so the value is routed to `mkRaw`, which aborts
      # with `mkRaw: invalid input: { __empty = null; }`.
      # Remove this whole key for manual-only formatting.
      format_on_save = {
        lsp_format = "fallback";
        timeout_ms = 5000;
      };

      formatters_by_ft = {
        c = [ "clang-format" ];
        cpp = [ "clang-format" ];
        rust = [ "rustfmt" ];

        # Kept even though `plugins.lsp.servers.ruff` is now enabled (the ruff server formats
        # too): with `lsp_format = "fallback"` only ONE of them runs - the CLI here, the LSP
        # only where no CLI formatter resolves. Same binary, same config discovery, and
        # formatting keeps working in a buffer with no client attached.
        # Prefer the server? Delete `ruff_format` below and `<leader>cf` falls through to it.
        python = [ "ruff_format" ];

        sh = [ "shfmt" ];
        bash = [ "shfmt" ];
        fish = [ "fish_indent" ];

        # nixd already formats via `formatting.command = [ "nixfmt" ]` (same binary), but
        # listing it here too means formatting works in a .nix buffer with no client attached.
        nix = [ "nixfmt" ];

        lua = [ "stylua" ];
        json = [ "jq" ];
        toml = [ "taplo" ];
      };
    };
  };

  # ---- Format keymaps ----
  # Deliberately top-level `keymaps`, NOT `plugins.lsp.keymaps`: those are emitted as
  # `keymapsOnEvents.LspAttach` (buffer-local, only after a client attached), which is
  # exactly backwards for conform - its whole reason to exist is the filetypes where no
  # LSP client attaches (fish, JSON with jsonls off, ...).
  keymaps = [
    {
      # NOTE: conform does **not** provide a `:Format` user command.
      # `grep -rn create_user_command` over the 9.1.0 source yields exactly one hit:
      # `:ConformInfo` in plugin/conform.lua. (`:Format` in the LazyVim sense is defined by
      # the *config*, not by the plugin.) Verified on the built nvim: `:Format` -> E492.
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
