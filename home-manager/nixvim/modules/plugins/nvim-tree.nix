{ ... }:
{
  # ---- Nvim-tree (file explorer) ----
  plugins.nvim-tree = {
    enable = true;

    settings = {
      # Track the buffer you are currently in: the tree expands/highlights the
      # open file when you switch buffers.
      # nixpkgs ships nvim-tree.lua 1.18 from the maintained nvim-tree org, where
      # this key is still `update_focused_file` (`filesystem.follow` is neo-tree).
      update_focused_file.enable = true;
    };
  };

  keymaps = [
    {
      key = "<leader>fs";
      action = "<Cmd>NvimTreeToggle<CR>";
      options.desc = "Toggle file tree";
    }
  ];
}
