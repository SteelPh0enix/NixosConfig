{ ... }:
{
  # Upstream defaults kept (nixvim matches todo-comments 1.5.0 1:1): colon-after-keyword is
  # required by both the highlight and the search pattern, which is the form used here;
  # `signs = true` is safe because `signcolumn = "yes"`.
  # `<leader>st` -> `:TodoFzfLua`, i.e. the generated ripgrep regex through fzf-lua's grep
  # provider. Don't add `keymaps.todoFzfLua.keywords`/`.cwd`: nixvim splices them in after
  # the call, where they either parse as a dead statement or E5107.
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

  # Also available without a keymap: `:TodoQuickFix`, `:TodoLocList`,
  # `require('todo-comments').enable()/.disable()`.
}
