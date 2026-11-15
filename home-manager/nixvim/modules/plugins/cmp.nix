_: {
  # VS Code-style icons in the completion menu; nixvim wires lspkind into cmp.
  plugins.lspkind.enable = true;

  # Confirming a completion inside brackets: autopairs has to be told, or `foo())` stays.
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
        # Menu first, then snippet placeholders; Neovim's own `vim.snippet` needs no engine.
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
          # Buffer words are the noisiest source; wait for longer words.
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
