{ ... }:
{
  # ---- Nvim-tree (file explorer) ----
  plugins.nvim-tree = {
    enable = true;
    openOnSetup = false;

    settings = {
      # Track the buffer you are currently in: the tree expands/highlights the
      # open file when you switch buffers.
      # NOTE: this is the option name for the nvim-tree.lua version packaged in
      # nixpkgs (archived kyazdani42 lineage, `update_focused_file`). The newer
      # maintained fork renamed it to `filesystem.follow = { enable, leave }`,
      # which this build rejects with "Unknown option: filesystem".
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
