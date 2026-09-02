{ ... }:
{
  imports = [
    # Core editor setup
    ./base.nix
    ./options.nix
    ./autocmds.nix
    ./keymaps.nix
    ./diagnostics.nix
    ./colorscheme.nix

    # Plugins (one file per plugin; keep in alphabetical order)
    ./plugins/cmp.nix
    ./plugins/conform-nvim.nix
    ./plugins/fzf-lua.nix
    ./plugins/gitsigns.nix
    ./plugins/lint.nix
    ./plugins/lsp.nix
    ./plugins/lualine.nix
    ./plugins/nvim-autopairs.nix
    ./plugins/nvim-lightbulb.nix
    ./plugins/nvim-tree.nix
    ./plugins/render-markdown.nix
    ./plugins/rustaceanvim.nix
    ./plugins/todo-comments.nix
    ./plugins/treesitter.nix
    ./plugins/web-devicons.nix
  ];
}
