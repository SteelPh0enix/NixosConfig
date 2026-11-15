_: {
  # `<leader>st` runs the generated ripgrep regex through fzf-lua. Do not add
  # keymaps.todoFzfLua.keywords/.cwd: nixvim splices them in after the call and they fail.
  plugins.todo-comments = {
    enable = true;

    keymaps.todoFzfLua.key = "<leader>st";
  };

  # Not `]t`/`[t`: Neovim 0.11+ owns those as tag-stack motions.
  keymaps = [
    {
      key = "<leader>tn";
      action.__raw = "function() require('todo-comments').jump_next() end";
      options.desc = "Next todo comment";
    }
    {
      key = "<leader>tp";
      action.__raw = "function() require('todo-comments').jump_prev() end";
      options.desc = "Previous todo comment";
    }
  ];
}
