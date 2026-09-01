{ ... }:
{
  # ---- Completion (nvim-cmp) ----
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
        "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), { 'i', 's' })";
        "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), { 'i', 's' })";
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
