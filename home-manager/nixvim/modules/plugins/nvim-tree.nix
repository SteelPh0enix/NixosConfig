{ ... }:
{
  plugins.nvim-tree = {
    enable = true;

    # Expand/highlight the tree on the currently open file. nixpkgs ships nvim-tree 1.18,
    # where the key is still `update_focused_file` (`filesystem.follow` is neo-tree).
    settings.update_focused_file.enable = true;
  };

  keymaps = [
    {
      key = "<leader>fs";
      action = "<Cmd>NvimTreeToggle<CR>";
      options.desc = "Toggle file tree";
    }
  ];
}
