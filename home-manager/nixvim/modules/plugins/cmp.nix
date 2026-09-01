{ ... }:
{
  # VS Code-style icons for the `kind` column of the completion menu. nixvim plugs
  # lspkind into `plugins.cmp.settings.formatting.format` automatically.
  plugins.lspkind.enable = true;

  # Confirming a completion inside brackets: autopairs has to be told about it,
  # otherwise the auto-inserted closing character stays and you get `foo())`.
  extraConfigLuaPost = ''
    require("cmp").event:on(
      "confirm_done",
      require("nvim-autopairs.completion.cmp").on_confirm_done()
    )
  '';

  # ---- Completion (nvim-cmp) ----
  plugins.cmp = {
    enable = true;
    autoEnableSources = true;

    settings = {
      completion = {
        keyword_length = 2;
        completeopt = "menu,menuone,noinsert,noselect";
      };

      # lspkind fills `kind` with an icon and `menu` with the source name.
      formatting.fields = [
        "kind"
        "abbr"
        "menu"
      ];

      window = {
        completion.border = "rounded";
        documentation.border = "rounded";
      };

      mapping = {
        "<C-Space>" = "cmp.mapping.complete()";
        "<C-d>" = "cmp.mapping.scroll_docs(-4)";
        "<C-f>" = "cmp.mapping.scroll_docs(4)";
        "<C-e>" = "cmp.mapping.close()";
        # Tab walks the completion menu first, then the placeholders of the snippet
        # that was just confirmed. nvim-cmp expands LSP snippets with Neovim's own
        # snippet engine (`vim.snippet`), so no extra plugin is needed for this.
        "<Tab>" = # lua
          ''
            cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_next_item()
              elseif vim.snippet.active({ direction = 1 }) then
                vim.snippet.jump(1)
              else
                fallback()
              end
            end, { "i", "s" })
          '';
        "<S-Tab>" = # lua
          ''
            cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_prev_item()
              elseif vim.snippet.active({ direction = -1 }) then
                vim.snippet.jump(-1)
              else
                fallback()
              end
            end, { "i", "s" })
          '';
        "<C-j>" = "cmp.mapping.select_next_item()";
        "<C-k>" = "cmp.mapping.select_prev_item()";
        "<CR>" = "cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Insert, select = false })";
        "<C-CR>" = "cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Insert, select = true })";
      };

      sources = [
        {
          name = "nvim_lsp";
          group_index = 1;
        }
        {
          name = "path";
          group_index = 1;
        }
        {
          name = "buffer";
          group_index = 2;
          # Buffer words are the noisiest source; only kick in for longer words
          # than the global keyword_length of 2.
          keyword_length = 3;
        }
      ];
    };

    # Command-line completion
    cmdline = {
      ":" = {
        completion.completeopt = "menu,menuone,noinsert";
        sources = [ { name = "cmdline"; } ];
      };
    };
  };
}
