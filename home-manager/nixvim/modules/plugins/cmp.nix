_: {
  # nixvim plugs lspkind into `plugins.cmp.settings.formatting.format` by itself.
  plugins.lspkind.enable = true;

  # autopairs has to be told, or the auto-inserted bracket leaves you with `foo())`.
  extraConfigLuaPost = ''
    require("cmp").event:on(
      "confirm_done",
      require("nvim-autopairs.completion.cmp").on_confirm_done()
    )
  '';

  plugins.cmp = {
    enable = true;
    autoEnableSources = true;

    settings = {
      completion = {
        keyword_length = 2;
        completeopt = "menu,menuone,noinsert,noselect";
      };

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
        # Menu first, then snippet placeholders; nvim-cmp uses Neovim's own `vim.snippet`.
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
          # Buffer words are the noisiest source: only for words longer than keyword_length.
          keyword_length = 3;
        }
      ];
    };

    cmdline = {
      ":" = {
        completion.completeopt = "menu,menuone,noinsert";
        sources = [ { name = "cmdline"; } ];
      };
    };
  };
}
