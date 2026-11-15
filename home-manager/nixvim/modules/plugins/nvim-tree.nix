_: {
  plugins.nvim-tree = {
    enable = true;

    # nvim-tree 1.18 still calls this `update_focused_file`.
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
