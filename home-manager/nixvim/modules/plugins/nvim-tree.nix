{ ... }:
{
  # ---- Nvim-tree (file explorer) ----
  plugins.nvim-tree = {
    enable = true;
    openOnSetup = false;
  };

  keymaps = [
    {
      key = "<leader>fs";
      action = "<Cmd>NvimTreeToggle<CR>";
      options.desc = "Toggle file tree";
    }
  ];
}
