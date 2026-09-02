{ ... }:
{
  # ---- gitsigns ----
  # gitsigns 2.1.0 ships *no* default keymaps (`grep -rn vim.keymap.set lua/gitsigns/`
  # only turns up the ones inside the blame/show_commit popups) and the nixvim module has
  # no keymap option - `settings.on_attach` is the only hook. Without this there is no
  # hunk workflow at all (`<leader>gc/gb/gt` are fzf-lua, not gitsigns).
  plugins.gitsigns = {
    enable = true;

    # `attach.lua` calls `config.on_attach(cbuf)`, so bind the buffer number explicitly
    # instead of `buffer = true` - gitsigns can attach to a buffer that is not the current
    # one (`:args`, `:LspInfo`-style bulk attaches, `+` arglists).
    settings.on_attach.__raw = ''
      function(bufnr)
        local map = function(lhs, rhs, desc)
          vim.keymap.set('n', lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
        end

        map(']c', '<Cmd>Gitsigns nav_hunk next<CR>', 'Next hunk')
        map('[c', '<Cmd>Gitsigns nav_hunk prev<CR>', 'Prev hunk')
        map('<leader>hs', '<Cmd>Gitsigns stage_hunk<CR>', 'Stage hunk')
        map('<leader>hr', '<Cmd>Gitsigns reset_hunk<CR>', 'Reset hunk')
        map('<leader>hp', '<Cmd>Gitsigns preview_hunk<CR>', 'Preview hunk')
        map('<leader>hb', '<Cmd>Gitsigns blame_line<CR>', 'Blame line')
        map('<leader>hq', '<Cmd>Gitsigns qflist<CR>', 'All hunks (quickfix)')
        map('<leader>ht', '<Cmd>Gitsigns toggle_deleted<CR>', 'Toggle deleted')
      end
    '';
  };
}
