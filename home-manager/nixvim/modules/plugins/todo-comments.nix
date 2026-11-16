_: {
  # Upstream defaults kept: colon-after-keyword is required by both the highlight and the search
  # pattern, and `signs = true` is safe because `signcolumn = "yes"`.
  # Don't add `keymaps.todoFzfLua.keywords`/`.cwd`: nixvim splices them in after the call, where
  # they parse as a dead statement or E5107.
  plugins.todo-comments = {
    enable = true;

    keymaps.todoFzfLua.key = "<leader>st";
  };

  # Not `]t`/`[t`: Neovim 0.11+ owns those as tag-stack motions (:tnext/:tprevious).
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
